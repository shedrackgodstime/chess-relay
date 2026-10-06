//! Phase 4 slice 4 spike: dropout, redial, tip compare, catch-up.
//!
//! Same isolation as slice 3 (throwaway framing, real `App` views).
//! After two agreed moves the guest drops mid-game; the host plays on
//! alone; the guest redials the same ticket, both compare tips, the host
//! replays the gap, agreement completes, and both assert identical FENs.

use chess_relay_core::app::{App, Command, Query, QueryResult};
use chess_relay_core::session::{LogEntry, LogPayload, PeerId};
use ed25519_dalek::SigningKey;
use iroh::{Endpoint, endpoint::presets};
use iroh_tickets::endpoint::EndpointTicket;
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// ALPN identifying chess-relay game traffic (plan Phase 4).
const ALPN: &[u8] = b"chess-relay/1";
/// Reserved voice ALPN: served on the same endpoint, unused in v1.
const VOICE_ALPN: &[u8] = b"chess-relay-voice/1";

/// Throwaway spike framing: one postcard message per uni stream.
#[derive(Debug, Serialize, Deserialize)]
enum Msg {
    Genesis(LogEntry),
    Ready {
        peer: PeerId,
        /// Guest's genesis co-signature (host needs it to note the join).
        #[serde(with = "serde_bytes")]
        genesis_sig: Option<[u8; 64]>,
    },
    Move(LogEntry),
    Agreed {
        seq: u64,
        #[serde(with = "serde_bytes")]
        sig: [u8; 64],
    },
    /// Resume request: next expected sequence plus tip hash.
    Tip {
        seq: u64,
        #[serde(with = "serde_bytes")]
        hash: [u8; 32],
    },
    /// Final position for cross-checking convergence.
    Fen {
        fen: String,
    },
    Done,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    match std::env::args().nth(1).as_deref() {
        Some("dial") => {
            let ticket = std::env::args()
                .nth(2)
                .ok_or_else(|| anyhow::anyhow!("usage: iroh_spike dial <ticket>"))?;
            guest(ticket.parse()?).await
        }
        _ => host().await,
    }
}

async fn bind() -> anyhow::Result<Endpoint> {
    let endpoint = Endpoint::builder(presets::N0)
        .alpns(vec![ALPN.to_vec(), VOICE_ALPN.to_vec()])
        .bind()
        .await?;
    println!("endpoint id: {}", endpoint.id());
    match tokio::time::timeout(Duration::from_secs(15), endpoint.online()).await {
        Ok(()) => println!("online via home relay"),
        Err(_) => println!("no relay yet — continuing local-only"),
    }
    Ok(endpoint)
}

async fn send_msg(connection: &iroh::endpoint::Connection, msg: &Msg) -> anyhow::Result<()> {
    let bytes = postcard::to_stdvec(msg)?;
    let mut send = connection.open_uni().await?;
    send.write_all(&(bytes.len() as u32).to_le_bytes()).await?;
    send.write_all(&bytes).await?;
    send.finish()?;
    Ok(())
}

async fn recv_msg(
    connection: &iroh::endpoint::Connection,
    timeout: Duration,
) -> anyhow::Result<Msg> {
    let recv_one = async {
        let mut recv = connection.accept_uni().await?;
        let mut len = [0u8; 4];
        recv.read_exact(&mut len).await?;
        let mut buf = vec![0u8; u32::from_le_bytes(len) as usize];
        recv.read_exact(&mut buf).await?;
        Ok::<_, anyhow::Error>(postcard::from_bytes(&buf)?)
    };
    match tokio::time::timeout(timeout, recv_one).await {
        Ok(result) => result,
        Err(_) => Err(anyhow::anyhow!("receive timed out")),
    }
}

fn move_log(app: &App) -> Vec<LogEntry> {
    match app.query(&Query::MoveLog).unwrap() {
        QueryResult::MoveLog(entries) => entries,
        _ => unreachable!(),
    }
}

fn game_fen(app: &App) -> String {
    match app.query(&Query::GameState).unwrap() {
        QueryResult::GameState(view) => view.fen,
        _ => unreachable!(),
    }
}

fn final_report(side: &str, app: &App) {
    let fen = match app.query(&Query::GameState).unwrap() {
        QueryResult::GameState(view) => view.fen,
        _ => unreachable!(),
    };
    let entries = move_log(app);
    let agreed = entries.iter().all(LogEntry::is_agreed);
    println!("{side} final-fen {fen}");
    println!("{side} entries={} all-agreed={agreed}", entries.len());
}

async fn host() -> anyhow::Result<()> {
    let endpoint = bind().await?;
    let ticket = EndpointTicket::new(endpoint.addr());
    println!("ticket: {ticket}");

    let host_key = SigningKey::from_bytes(&[1u8; 32]);
    let guest_key = SigningKey::from_bytes(&[2u8; 32]);
    let (white, black) = (PeerId::of(&host_key), PeerId::of(&guest_key));
    let mut app = App::with_local(host_key);
    app.admit(guest_key);
    app.handle(&Command::StartGame { white, black })?;

    println!("waiting for guest (120s)...");
    let incoming = tokio::time::timeout(Duration::from_secs(120), endpoint.accept())
        .await?
        .ok_or_else(|| anyhow::anyhow!("endpoint closed"))?;
    let connection = incoming.await?;
    println!("guest connected");

    // Genesis crosses; guest joins off it.
    send_msg(&connection, &Msg::Genesis(move_log(&app)[0])).await?;

    // Guest readiness + genesis co-signature arrive; host joins them in.
    let Msg::Ready { peer, genesis_sig } = recv_msg(&connection, Duration::from_secs(60)).await?
    else {
        anyhow::bail!("expected Ready from guest");
    };
    let co_sig = genesis_sig.ok_or_else(|| anyhow::anyhow!("guest sent no co-signature"))?;
    app.handle(&Command::NotePeerJoined { peer, co_sig })?;
    app.handle(&Command::NotePeerReady { peer })?;
    app.handle(&Command::SetReady { peer: white })?;
    send_msg(
        &connection,
        &Msg::Ready {
            peer: white,
            genesis_sig: None,
        },
    )
    .await?;

    // Round 1: host moves, guest ingests and agrees back.
    app.handle(&Command::SubmitMove {
        peer: white,
        mv: "e2e4".parse()?,
    })?;
    send_msg(&connection, &Msg::Move(*move_log(&app).last().unwrap())).await?;
    let Msg::Agreed { seq, sig } = recv_msg(&connection, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected Agreed from guest");
    };
    app.handle(&Command::NoteMoveAgreed { seq, co_sig: sig })?;

    // Round 2: guest moves; host ingests, agrees, reports the gap point.
    let Msg::Move(entry) = recv_msg(&connection, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected Move from guest");
    };
    app.ingest_remote(&entry)?;
    for event in app.drain() {
        println!("host event: {event:?}");
    }
    let entries = move_log(&app);
    let agreed = entries.last().unwrap();
    let (seq, sig) = (agreed.seq, agreed.co_sig.unwrap());
    send_msg(&connection, &Msg::Agreed { seq, sig }).await?;

    // Guest drops mid-game (no Done arrives); host plays on alone.
    match recv_msg(&connection, Duration::from_secs(60)).await {
        Ok(Msg::Done) => println!("guest left cleanly (unexpected in this script)"),
        Ok(other) => println!("guest sent {other:?} instead of Done; treating as dropout"),
        Err(err) => println!("guest dropped ({err}); playing on alone"),
    }
    app.handle(&Command::SubmitMove {
        peer: white,
        mv: "g1f3".parse()?,
    })?;
    println!("host played g1f3 alone; waiting for redial (120s)...");

    // Guest redials the same ticket; compare tips and replay the gap.
    let incoming = tokio::time::timeout(Duration::from_secs(120), endpoint.accept())
        .await?
        .ok_or_else(|| anyhow::anyhow!("endpoint closed"))?;
    let redial = incoming.await?;
    println!("guest redialled");
    let Msg::Tip {
        seq: guest_seq,
        hash: guest_hash,
    } = recv_msg(&redial, Duration::from_secs(60)).await?
    else {
        anyhow::bail!("expected Tip from guest");
    };
    let entries = move_log(&app);
    println!(
        "tip compare: guest seq={guest_seq} host seq={} (hashes {})",
        entries.len(),
        if entries.last().map(|entry| entry.hash()) == Some(guest_hash) {
            "match (nothing missing)"
        } else {
            "differ (replaying gap)"
        }
    );
    let mut sent = 0;
    for entry in entries.iter().filter(|entry| entry.seq >= guest_seq) {
        let LogPayload::Move { .. } = entry.payload else {
            anyhow::bail!("catch-up only replays moves in this script");
        };
        send_msg(&redial, &Msg::Move(*entry)).await?;
        let Msg::Agreed { seq, sig } = recv_msg(&redial, Duration::from_secs(60)).await? else {
            anyhow::bail!("expected Agreed from guest");
        };
        app.handle(&Command::NoteMoveAgreed { seq, co_sig: sig })?;
        sent += 1;
    }
    println!("replayed {sent} missing entries");

    // Both assert the same final position, then close.
    let local_fen = game_fen(&app);
    send_msg(
        &redial,
        &Msg::Fen {
            fen: local_fen.clone(),
        },
    )
    .await?;
    let Msg::Fen { fen: remote_fen } = recv_msg(&redial, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected Fen from guest");
    };
    assert_eq!(local_fen, remote_fen, "views diverged after resume");
    println!("FENs match after resume");
    send_msg(&redial, &Msg::Done).await?;
    let Msg::Done = recv_msg(&redial, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected Done from guest");
    };
    final_report("host", &app);
    redial.close(0u32.into(), b"game over");
    endpoint.close().await;
    println!("spike done");
    Ok(())
}

async fn guest(ticket: EndpointTicket) -> anyhow::Result<()> {
    let endpoint = bind().await?;
    let connection = tokio::time::timeout(
        Duration::from_secs(60),
        endpoint.connect(ticket.endpoint_addr().clone(), ALPN),
    )
    .await??;
    println!("connected to host");

    let guest_key = SigningKey::from_bytes(&[2u8; 32]);
    let host_key = SigningKey::from_bytes(&[1u8; 32]);
    let black = PeerId::of(&guest_key);
    let mut app = App::with_local(guest_key);
    app.admit(host_key);

    // Join off the host's genesis; announce readiness.
    let Msg::Genesis(genesis) = recv_msg(&connection, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected Genesis from host");
    };
    app.handle(&Command::JoinGame {
        peer: black,
        genesis: Box::new(genesis),
    })?;
    app.handle(&Command::SetReady { peer: black })?;
    let co_sig = move_log(&app)[0].co_sig.unwrap();
    send_msg(
        &connection,
        &Msg::Ready {
            peer: black,
            genesis_sig: Some(co_sig),
        },
    )
    .await?;

    // Host readies; round 1 move arrives, ingested and agreed.
    let Msg::Ready { peer, .. } = recv_msg(&connection, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected Ready from host");
    };
    app.handle(&Command::NotePeerReady { peer })?;
    let Msg::Move(entry) = recv_msg(&connection, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected Move from host");
    };
    app.ingest_remote(&entry)?;
    for event in app.drain() {
        println!("guest event: {event:?}");
    }
    let entries = move_log(&app);
    let agreed = entries.last().unwrap();
    send_msg(
        &connection,
        &Msg::Agreed {
            seq: agreed.seq,
            sig: agreed.co_sig.unwrap(),
        },
    )
    .await?;

    // Round 2: guest moves; host agrees back.
    app.handle(&Command::SubmitMove {
        peer: black,
        mv: "e7e5".parse()?,
    })?;
    send_msg(&connection, &Msg::Move(*move_log(&app).last().unwrap())).await?;
    let Msg::Agreed { seq, sig } = recv_msg(&connection, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected Agreed from host");
    };
    app.handle(&Command::NoteMoveAgreed { seq, co_sig: sig })?;

    // Drop mid-game (no Done), wait, redial the same ticket.
    println!("guest dropping mid-game...");
    connection.close(0u32.into(), b"dropout");
    tokio::time::sleep(Duration::from_secs(3)).await;
    let redial = tokio::time::timeout(
        Duration::from_secs(60),
        endpoint.connect(ticket.endpoint_addr().clone(), ALPN),
    )
    .await??;
    println!("guest redialled");
    let entries = move_log(&app);
    let tip_hash = entries
        .last()
        .map(|entry| entry.hash())
        .unwrap_or([0u8; 32]);
    send_msg(
        &redial,
        &Msg::Tip {
            seq: entries.len() as u64,
            hash: tip_hash,
        },
    )
    .await?;

    // Replay the gap until the host sends its position.
    loop {
        match recv_msg(&redial, Duration::from_secs(60)).await? {
            Msg::Move(entry) => {
                app.ingest_remote(&entry)?;
                let entries = move_log(&app);
                let agreed = entries.last().unwrap();
                send_msg(
                    &redial,
                    &Msg::Agreed {
                        seq: agreed.seq,
                        sig: agreed.co_sig.unwrap(),
                    },
                )
                .await?;
            }
            Msg::Fen { fen: remote_fen } => {
                let local_fen = game_fen(&app);
                assert_eq!(local_fen, remote_fen, "views diverged after resume");
                println!("FENs match after resume");
                send_msg(&redial, &Msg::Fen { fen: local_fen }).await?;
                break;
            }
            other => anyhow::bail!("unexpected {other:?} during catch-up"),
        }
    }
    let Msg::Done = recv_msg(&redial, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected Done from host");
    };
    send_msg(&redial, &Msg::Done).await?;
    final_report("guest", &app);
    redial.closed().await;
    endpoint.close().await;
    println!("spike done");
    Ok(())
}

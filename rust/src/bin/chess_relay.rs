//! Two-peer chess over Iroh: the transport slice proven end to end.
//!
//! Usage:
//!   chess_relay host [--code CODE]   # prints TICKET: ... (and CODE)
//!   chess_relay join <ticket|code>
//!
//! A ticket dials directly (cryptographic addressing). A short code
//! resolves through pkarr rendezvous first. Identity follows the arch
//! doc: one fresh 32-byte seed per run builds both the Iroh endpoint key
//! and the session signing key, and each side asserts the bytes match.
//!
//! Everything here goes through the [`transport`](chess_relay_core::transport)
//! traits plus [`App`](chess_relay_core::app); no Iroh or session types
//! leak into the flow logic.

use chess_relay_core::app::{App, Command, Event, Query, QueryResult};
use chess_relay_core::protocol::{Msg, PROTOCOL_VERSION};
use chess_relay_core::session::{LogEntry, PeerId};
use chess_relay_core::transport::{Connection, Endpoint};
use chess_relay_core::{IrohConnection, IrohEndpoint};
use ed25519_dalek::SigningKey;
use std::time::Duration;

fn fresh_seed() -> [u8; 32] {
    let mut seed = [0u8; 32];
    getrandom::getrandom(&mut seed).expect("randomness available");
    seed
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

async fn recv(connection: &mut IrohConnection, timeout: Duration) -> anyhow::Result<Msg> {
    match tokio::time::timeout(timeout, connection.recv()).await {
        Ok(result) => result.map_err(anyhow::Error::from),
        Err(_) => Err(anyhow::anyhow!("receive timed out")),
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("join") => {
            let target = args
                .next()
                .ok_or_else(|| anyhow::anyhow!("usage: chess_relay join <ticket|code>"))?;
            join(&target).await
        }
        Some("host") => {
            let code = args.next().filter(|flag| flag == "--code").and(args.next());
            host(code).await
        }
        _ => host(None).await,
    }
}

async fn host(code: Option<String>) -> anyhow::Result<()> {
    let seed = fresh_seed();
    let mut endpoint = IrohEndpoint::bind_with_seed(seed).await?;
    let secret = SigningKey::from_bytes(&seed);
    assert_eq!(
        endpoint.id_bytes(),
        PeerId::of(&secret).bytes(),
        "endpoint identity must equal peer identity"
    );
    let host_peer = PeerId::of(&secret);
    println!("TICKET: {}", endpoint.ticket());
    let _publisher = match code.clone() {
        Some(code) => {
            println!("CODE: {code}");
            let ticket: iroh_tickets::endpoint::EndpointTicket = endpoint.ticket().parse()?;
            let code_clone = code.clone();
            let ticket_clone = ticket;
            Some(tokio::spawn(async move {
                chess_relay_core::publish_loop(code_clone, ticket_clone).await;
            }))
        }
        None => None,
    };

    let mut app = App::with_local(secret);
    println!("waiting for guest (120s)...");
    let mut connection = endpoint.accept().await?;
    let guest_peer = PeerId::from_bytes(connection.peer_id_bytes());
    println!("guest arrived: {guest_peer}");

    connection
        .send(&Msg::LobbyHello {
            version: PROTOCOL_VERSION,
        })
        .await?;
    let Msg::LobbyHello { version } = recv(&mut connection, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected lobby greeting from guest");
    };
    assert_eq!(version, PROTOCOL_VERSION, "version gate");

    app.handle(&Command::StartGame {
        white: host_peer,
        black: guest_peer,
    })?;
    let genesis = move_log(&app)[0];
    connection
        .send(&Msg::Hello {
            version: PROTOCOL_VERSION,
            genesis,
        })
        .await?;

    let Msg::Ready { peer } = recv(&mut connection, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected Ready from guest");
    };
    let Msg::Agreed { seq, sig } = recv(&mut connection, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected genesis agreement from guest");
    };
    assert_eq!(seq, 0, "first agreement covers genesis");
    app.handle(&Command::NotePeerJoined { peer, co_sig: sig })?;
    app.handle(&Command::NotePeerReady { peer })?;
    app.handle(&Command::SetReady { peer: host_peer })?;
    connection.send(&Msg::Started).await?;

    play_round(&mut app, &mut connection, host_peer, "e2e4").await?;
    receive_round(&mut app, &mut connection).await?;
    finish(&mut app, &mut connection, "host").await?;
    if let Some(code) = code {
        chess_relay_core::unpublish(&code).await;
    }
    endpoint.close().await;
    println!("cli done");
    Ok(())
}

async fn join(target: &str) -> anyhow::Result<()> {
    let seed = fresh_seed();
    let mut endpoint = IrohEndpoint::bind_with_seed(seed).await?;
    let secret = SigningKey::from_bytes(&seed);
    assert_eq!(
        endpoint.id_bytes(),
        PeerId::of(&secret).bytes(),
        "endpoint identity must equal peer identity"
    );
    let guest_peer = PeerId::of(&secret);
    // Tickets dial directly; short codes resolve through rendezvous first.
    let ticket = match target.parse::<iroh_tickets::endpoint::EndpointTicket>() {
        Ok(ticket) => ticket,
        Err(_) => {
            println!("resolving code {target}...");
            chess_relay_core::resolve_ticket(target, Duration::from_secs(120)).await?
        }
    };
    let mut connection = endpoint.connect(&ticket.to_string()).await?;
    println!("connected to host");
    let host_peer = PeerId::from_bytes(connection.peer_id_bytes());

    connection
        .send(&Msg::LobbyHello {
            version: PROTOCOL_VERSION,
        })
        .await?;
    let Msg::LobbyHello { version } = recv(&mut connection, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected lobby greeting from host");
    };
    assert_eq!(version, PROTOCOL_VERSION, "version gate");

    let mut app = App::with_local(secret);
    let Msg::Hello { version, genesis } = recv(&mut connection, Duration::from_secs(60)).await?
    else {
        anyhow::bail!("expected Hello from host");
    };
    assert_eq!(version, PROTOCOL_VERSION, "version gate");
    app.handle(&Command::JoinGame {
        peer: guest_peer,
        genesis: Box::new(genesis),
    })?;
    connection.send(&Msg::Ready { peer: guest_peer }).await?;
    let co_sig = move_log(&app)[0].co_sig.unwrap();
    connection
        .send(&Msg::Agreed {
            seq: 0,
            sig: co_sig,
        })
        .await?;

    let Msg::Started = recv(&mut connection, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected Started from host");
    };
    app.handle(&Command::NotePeerReady { peer: host_peer })?;
    app.handle(&Command::SetReady { peer: guest_peer })?;
    receive_round(&mut app, &mut connection).await?;
    play_round(&mut app, &mut connection, guest_peer, "e7e5").await?;
    finish(&mut app, &mut connection, "guest").await?;
    endpoint.close().await;
    println!("cli done");
    Ok(())
}

/// Submits a scripted move, sends the entry, and absorbs the co-signature.
async fn play_round(
    app: &mut App,
    connection: &mut IrohConnection,
    peer: PeerId,
    uci: &str,
) -> anyhow::Result<()> {
    app.handle(&Command::SubmitMove {
        peer,
        mv: uci.parse()?,
    })?;
    connection
        .send(&Msg::Entry(*move_log(app).last().unwrap()))
        .await?;
    let Msg::Agreed { seq, sig } = recv(connection, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected Agreed");
    };
    app.handle(&Command::NoteMoveAgreed { seq, co_sig: sig })?;
    Ok(())
}

/// Ingests a move, agrees locally, and sends the co-signature back.
async fn receive_round(app: &mut App, connection: &mut IrohConnection) -> anyhow::Result<()> {
    let Msg::Entry(entry) = recv(connection, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected Entry");
    };
    app.ingest_remote(&entry)?;
    for event in app.drain() {
        if let Event::MoveApplied { seq, mv, .. } = event {
            println!("applied {mv} at seq {seq}");
        }
    }
    let entries = move_log(app);
    let agreed = entries.last().unwrap();
    let (seq, sig) = (agreed.seq, agreed.co_sig.unwrap());
    connection.send(&Msg::Agreed { seq, sig }).await?;
    Ok(())
}

/// Exchanges final positions and asserts convergence.
async fn finish(app: &mut App, connection: &mut IrohConnection, side: &str) -> anyhow::Result<()> {
    let local_fen = game_fen(app);
    connection
        .send(&Msg::Fen {
            fen: local_fen.clone(),
        })
        .await?;
    let Msg::Fen { fen: remote_fen } = recv(connection, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected Fen");
    };
    assert_eq!(local_fen, remote_fen, "views diverged");
    println!("{side} final-fen {local_fen}");
    connection.send(&Msg::Done).await?;
    let Msg::Done = recv(connection, Duration::from_secs(60)).await? else {
        anyhow::bail!("expected Done");
    };
    Ok(())
}

//! Interactive host for playing a real game against the Godot client over Iroh.
//!
//! Usage:
//!   chess_play_host [--black] [--code CODE]
//!
//! Flow (mirrors `bridge.rs` drive_session/on_msg for AcceptMode::Game):
//!   1. Bind endpoint, wait briefly for relay readiness, print TICKET + CODE.
//!   2. Accept one guest, exchange LobbyHello.
//!   3. StartGame immediately (host White by default), send Hello + Setup.
//!   4. Complete handshake: expect guest Agreed(0) + Ready (any order),
//!      then send Started.
//!   5. Interactive move loop: stdin UCI lines on our turn, Entry/Agreed
//!      exchange on the wire, FEN printed after every change.
//!
//! Stdin commands: `<uci>` (e.g. e2e4), `/quit`, `/resign`.

use chess_relay_core::app::{App, Command, Event, Query, QueryResult};
use chess_relay_core::protocol::{Msg, PROTOCOL_VERSION};
use chess_relay_core::session::PeerId;
use chess_relay_core::transport::{Connection, Endpoint};
use chess_relay_core::{IrohConnection, IrohEndpoint};
use ed25519_dalek::SigningKey;
use std::time::Duration;

const CODE_ALPHABET: &[u8] = b"23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

fn fresh_seed() -> [u8; 32] {
    let mut seed = [0u8; 32];
    getrandom::getrandom(&mut seed).expect("randomness available");
    seed
}

fn random_code() -> String {
    let mut buf = [0u8; 8];
    getrandom::getrandom(&mut buf).expect("randomness available");
    buf.iter()
        .map(|b| CODE_ALPHABET[(usize::from(*b)) % CODE_ALPHABET.len()] as char)
        .collect()
}

fn move_log(app: &App) -> Vec<chess_relay_core::session::LogEntry> {
    match app.query(&Query::MoveLog).unwrap() {
        QueryResult::MoveLog(entries) => entries,
        _ => unreachable!(),
    }
}

#[allow(dead_code)]
fn game_fen(app: &App) -> String {
    match app.query(&Query::GameState).unwrap() {
        QueryResult::GameState(view) => view.fen,
        _ => unreachable!(),
    }
}

fn print_position(app: &App, me: &PeerId, white: &PeerId, black: &PeerId) {
    let view = match app.query(&Query::GameState).unwrap() {
        QueryResult::GameState(v) => v,
        _ => unreachable!(),
    };
    let my_side = if me == white {
        "White"
    } else if me == black {
        "Black"
    } else {
        "?"
    };
    let turn = format!("{:?}", view.side_to_move);
    let outcome = format!("{:?}", view.outcome);
    println!("---");
    println!("FEN: {}", view.fen);
    println!("turn: {turn} | you: {my_side} ({me}) | outcome: {outcome}");
    if !view.check.is_empty() {
        println!("check: {}", view.check);
    }
    let log = move_log(app);
    let moves: Vec<String> = log
        .iter()
        .filter(|e| e.seq > 0)
        .map(|e| format!("#{} {:?}", e.seq, e.payload))
        .collect();
    if !moves.is_empty() {
        println!("log: {}", moves.join(" "));
    }
}

async fn recv(conn: &mut IrohConnection, timeout: Duration) -> anyhow::Result<Msg> {
    match tokio::time::timeout(timeout, conn.recv()).await {
        Ok(r) => r.map_err(anyhow::Error::from),
        Err(_) => Err(anyhow::anyhow!("receive timed out")),
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let play_black = args.iter().any(|a| a == "--black");
    let code = {
        let mut c: Option<String> = None;
        let mut i = 0;
        while i < args.len() {
            if args[i] == "--code" && i + 1 < args.len() {
                c = Some(args[i + 1].clone());
                break;
            }
            i += 1;
        }
        c.unwrap_or_else(random_code)
    };

    let seed = fresh_seed();
    let mut endpoint = IrohEndpoint::bind_with_seed(seed).await?;
    let secret = SigningKey::from_bytes(&seed);
    assert_eq!(
        endpoint.id_bytes(),
        PeerId::of(&secret).bytes(),
        "endpoint identity must equal peer identity"
    );
    let host_peer = PeerId::of(&secret);
    let _ = endpoint.wait_online(Duration::from_secs(10)).await;

    let ticket = endpoint.ticket();
    println!("TICKET: {ticket}");
    println!("CODE: {code}");
    println!("(In Godot: Multiplayer hub -> Join -> enter CODE or TICKET)");

    let parsed: iroh_tickets::endpoint::EndpointTicket = ticket.parse()?;
    let code_clone = code.clone();
    let ticket_clone = parsed.clone();
    tokio::spawn(async move {
        chess_relay_core::publish_loop(code_clone, ticket_clone).await;
    });

    // No timeout: a human needs as long as a human needs. The lobby
    // stays open until a guest arrives or the host is killed.
    println!("waiting for guest (no timeout)...");
    let mut conn = endpoint.accept().await?;
    let guest_peer = PeerId::from_bytes(conn.peer_id_bytes());
    println!("guest arrived: {guest_peer}");

    // Lobby handshake (both sides send LobbyHello in bridge drive_session).
    conn.send(&Msg::LobbyHello {
        version: PROTOCOL_VERSION,
        ticket: ticket.clone(),
    })
    .await?;
    let Msg::LobbyHello { version, .. } = recv(&mut conn, Duration::from_secs(120)).await? else {
        anyhow::bail!("expected LobbyHello from guest");
    };
    if version != PROTOCOL_VERSION {
        anyhow::bail!("version mismatch: guest speaks {version}");
    }

    let (white, black) = if play_black {
        (guest_peer, host_peer)
    } else {
        (host_peer, guest_peer)
    };
    let mut app = App::with_local(secret);
    app.handle(&Command::StartGame { white, black })?;
    let genesis = move_log(&app)[0];
    conn.send(&Msg::Hello {
        version: PROTOCOL_VERSION,
        genesis,
    })
    .await?;
    conn.send(&Msg::Setup {
        revision: 1,
        side: if play_black {
            "Black".into()
        } else {
            "White".into()
        },
        time: "-".into(),
        variant: "Standard".into(),
    })
    .await?;
    println!(
        "game created: you play {}",
        if play_black { "Black" } else { "White" }
    );

    // Handshake completion: guest sends Agreed(0) + Ready in either order.
    let mut agreed = false;
    let mut ready = false;
    let mut ready_sent = false;
    for _ in 0..10 {
        if agreed && ready {
            break;
        }
        let msg = recv(&mut conn, Duration::from_secs(120)).await?;
        match msg {
            Msg::Agreed { seq: 0, sig } => {
                app.handle(&Command::NotePeerJoined {
                    peer: guest_peer,
                    co_sig: sig,
                })?;
                app.handle(&Command::SetReady { peer: host_peer })?;
                conn.send(&Msg::Ready { peer: host_peer }).await?;
                ready_sent = true;
                agreed = true;
                println!("guest agreed genesis; host ready sent");
            }
            Msg::Ready { peer } => {
                app.handle(&Command::NotePeerReady { peer })?;
                ready = true;
                println!("guest ready: {peer}");
            }
            Msg::Loaded => {
                println!("guest board loaded");
            }
            Msg::Setup { .. } => {}
            other => {
                println!("(ignoring {other:?} during handshake)");
            }
        }
    }
    anyhow::ensure!(agreed, "handshake failed: no genesis agreement");
    anyhow::ensure!(ready, "handshake failed: guest never ready");
    if !ready_sent {
        conn.send(&Msg::Ready { peer: host_peer }).await?;
    }
    conn.send(&Msg::Started).await?;
    // The Godot game screen keeps the board hidden until BOTH sides have
    // sent Loaded (see game_screen.gd _reveal_network_board). The old
    // scripted CLI never sent it, so the guest board stayed invisible.
    conn.send(&Msg::Loaded).await?;
    let mut loaded_sent = true;
    println!("both ready — game started. Type UCI moves (e2e4) or /quit.");

    // Stdin reader thread -> channel (avoids needing tokio io-std feature).
    let (stdin_tx, mut stdin_rx) = tokio::sync::mpsc::unbounded_channel::<String>();
    std::thread::spawn(move || {
        let stdin = std::io::stdin();
        let mut line = String::new();
        use std::io::BufRead as _;
        let mut locked = stdin.lock();
        loop {
            line.clear();
            match locked.read_line(&mut line) {
                Ok(0) => break,
                Ok(_) => {
                    let _ = stdin_tx.send(line.trim().to_string());
                }
                Err(_) => break,
            }
        }
    });

    print_position(&app, &host_peer, &white, &black);

    loop {
        // Check terminal outcome.
        let outcome_done = match app.query(&Query::GameState).unwrap() {
            QueryResult::GameState(v) => {
                !matches!(v.outcome, chess_relay_core::chess_core::Outcome::Ongoing)
            }
            _ => false,
        };
        if outcome_done {
            let view = match app.query(&Query::GameState).unwrap() {
                QueryResult::GameState(v) => v,
                _ => unreachable!(),
            };
            println!("GAME OVER: {:?}", view.outcome);
            println!("final FEN: {}", view.fen);
            println!("Type /quit to close, or keep watching.");
        }

        // Whose turn? Derive from GameState side_to_move vs our color.
        let my_turn = match app.query(&Query::GameState).unwrap() {
            QueryResult::GameState(v) => {
                let my_color = if host_peer == white {
                    chess_relay_core::chess_core::Color::White
                } else {
                    chess_relay_core::chess_core::Color::Black
                };
                v.side_to_move == my_color
                    && matches!(v.outcome, chess_relay_core::chess_core::Outcome::Ongoing)
            }
            _ => false,
        };
        if my_turn {
            println!("your move (UCI):");
        }

        tokio::select! {
            line = stdin_rx.recv() => {
                let Some(line) = line else { break; };
                let line = line.trim().to_string();
                if line.is_empty() { continue; }
                if line == "/quit" {
                    let _ = conn.send(&Msg::Leave).await;
                    break;
                }
                if line == "/resign" {
                    app.handle(&Command::Resign { peer: host_peer })?;
                    let entry = *move_log(&app).last().unwrap();
                    conn.send(&Msg::Entry(entry)).await?;
                    print_position(&app, &host_peer, &white, &black);
                    continue;
                }
                if line.starts_with('/') {
                    println!("unknown command {line}; try <uci> e.g. e2e4, /resign, /quit");
                    continue;
                }
                let mv: chess_relay_core::chess_core::Move = match line.parse() {
                    Ok(m) => m,
                    Err(e) => { println!("bad UCI '{line}': {e}"); continue; }
                };
                match app.handle(&Command::SubmitMove { peer: host_peer, mv }) {
                    Ok(events) => {
                        for e in events {
                            if let Event::MoveApplied { seq, mv, .. } = e {
                                println!("you played {mv} at seq {seq}");
                            }
                        }
                        let entry = *move_log(&app).last().unwrap();
                        conn.send(&Msg::Entry(entry)).await?;
                        print_position(&app, &host_peer, &white, &black);
                    }
                    Err(e) => println!("rejected: {e}"),
                }
            }
            msg = conn.recv() => {
                let msg = match msg {
                    Ok(m) => m,
                    Err(e) => { println!("connection lost: {e}"); break; }
                };
                match msg {
                    Msg::Entry(entry) => {
                        match app.ingest_remote(&entry) {
                            Ok(()) => {
                                for e in app.drain() {
                                    if let Event::MoveApplied { seq, mv, .. } = e {
                                        println!("guest played {mv} at seq {seq}");
                                    }
                                }
                                let tip = *move_log(&app).last().unwrap();
                                if let Some(sig) = tip.co_sig {
                                    conn.send(&Msg::Agreed { seq: tip.seq, sig }).await?;
                                }
                                print_position(&app, &host_peer, &white, &black);
                            }
                            Err(e) => println!("remote entry rejected: {e}"),
                        }
                    }
                    Msg::Agreed { seq, sig } => {
                        match app.handle(&Command::NoteMoveAgreed { seq, co_sig: sig }) {
                            Ok(events) => {
                                for e in events {
                                    if let Event::MoveAgreed { seq } = e {
                                        println!("guest co-signed seq {seq}");
                                    }
                                }
                                print_position(&app, &host_peer, &white, &black);
                            }
                            Err(e) => println!("agreement rejected: {e}"),
                        }
                    }
                    Msg::Ready { peer } => {
                        let _ = app.handle(&Command::NotePeerReady { peer });
                        println!("(guest ready ping: {peer})");
                    }
                    Msg::Loaded => {
                        println!("(guest board loaded)");
                        if !loaded_sent {
                            conn.send(&Msg::Loaded).await?;
                            loaded_sent = true;
                        }
                    }
                    Msg::Leave => { println!("guest left the game"); break; }
                    Msg::Done => { println!("guest sent Done"); break; }
                    Msg::Setup { side, time, variant, .. } => {
                        println!("(guest setup echo: {side} {time} {variant})");
                    }
                    Msg::LobbyHello { .. } | Msg::Hello { .. } | Msg::Started => {
                        println!("(duplicate handshake msg ignored)");
                    }
                    Msg::Resume { .. } | Msg::Tip { .. } | Msg::Fen { .. } => {}
                    Msg::InviteRequest { .. } | Msg::InviteResponse { .. }
                    | Msg::RematchRequest { .. } | Msg::RematchResponse { .. } => {
                        println!("(invite/rematch msg ignored in direct game)");
                    }
                }
            }
        }
    }

    chess_relay_core::unpublish(&code).await;
    endpoint.close().await;
    println!("host done");
    Ok(())
}

//! Login, restore, room listing, messages, continuous sync and logout
//! against a real homeserver.
//!
//! Ignored by default: it needs network access and a real account, provided
//! through environment variables (never commit credentials):
//!
//! ```bash
//! MATRIX_HOMESERVER=https://matrix.org MATRIX_USERNAME=alice MATRIX_PASSWORD=... \
//!     cargo test --test live_login -- --ignored --nocapture
//! ```
//!
//! Optional: `MATRIX_TEST_ROOM_ID=!room:server` also loads that room's latest
//! messages. Only if `MATRIX_TEST_SEND=1` is set too, a test message is
//! **sent** to that room.

use messenger_core::{CoreEvent, LogoutOutcome, MessengerCore, RestoreOutcome, SyncState};

fn env(name: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| panic!("{name} must be set"))
}

#[tokio::test]
#[ignore = "requires a real homeserver and MATRIX_* credentials"]
async fn session_and_rooms_on_a_real_homeserver() {
    let homeserver = env("MATRIX_HOMESERVER");
    let data_dir = tempfile::tempdir().expect("temporary data dir");

    let mut core = MessengerCore::new(&homeserver, data_dir.path())
        .await
        .expect("valid homeserver");
    core.login(&env("MATRIX_USERNAME"), &env("MATRIX_PASSWORD"))
        .await
        .expect("login succeeds");
    let user = core.current_user().expect("authenticated user");
    println!("logged in as {user}");
    drop(core);

    let mut core = MessengerCore::new(&homeserver, data_dir.path())
        .await
        .expect("valid homeserver");
    assert_eq!(
        core.restore_session().await.expect("restore succeeds"),
        RestoreOutcome::Restored
    );
    assert_eq!(core.current_user(), Some(user));

    let rooms = core.refresh_rooms().await.expect("sync succeeds");
    println!("{} joined room(s)", rooms.len());
    for room in &rooms {
        println!("- {} (direct: {})", room.display_name, room.is_direct);
    }

    if let Ok(room_id) = std::env::var("MATRIX_TEST_ROOM_ID") {
        let messages = core
            .load_messages(&room_id, 20)
            .await
            .expect("messages load");
        println!("{} message(s) in {room_id}", messages.len());

        if std::env::var("MATRIX_TEST_SEND").as_deref() == Ok("1") {
            let sent = core
                .send_text_message(&room_id, "messenger_core live test")
                .await
                .expect("message sent");
            println!("sent {}", sent.event_id);
        }
    }

    // Continuous sync: wait (bounded) until it is up to date, then stop.
    let mut events = core.subscribe_events();
    core.start_sync().await.expect("sync starts");
    tokio::time::timeout(std::time::Duration::from_secs(60), async {
        while let Some(event) = events.recv().await {
            println!("event: {event:?}");
            if event == CoreEvent::SyncStateChanged(SyncState::Running) {
                return;
            }
        }
    })
    .await
    .expect("sync reaches Running");
    core.stop_sync().await.expect("sync stops");

    assert_eq!(
        core.logout().await.expect("logout succeeds"),
        LogoutOutcome::Complete
    );
}

//! Login against a real homeserver.
//!
//! Ignored by default: it needs network access and a real account, provided
//! through environment variables (never commit credentials):
//!
//! ```bash
//! MATRIX_HOMESERVER=https://matrix.org MATRIX_USERNAME=alice MATRIX_PASSWORD=... \
//!     cargo test --test live_login -- --ignored
//! ```

use messenger_core::MessengerCore;

fn env(name: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| panic!("{name} must be set"))
}

#[tokio::test]
#[ignore = "requires a real homeserver and MATRIX_* credentials"]
async fn logs_in_to_a_real_homeserver() {
    let mut core = MessengerCore::new(&env("MATRIX_HOMESERVER"))
        .await
        .expect("valid homeserver");

    core.login(&env("MATRIX_USERNAME"), &env("MATRIX_PASSWORD"))
        .await
        .expect("login succeeds");

    let user = core.current_user().expect("authenticated user");
    println!("logged in as {user}");
}

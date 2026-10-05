//! Native core of the desktop messaging client.
//!
//! This crate will host the Matrix integration (built on [`matrix_sdk`]) and
//! later be exposed to the Flutter application through Flutter Rust Bridge.
//!
//! At this stage it only establishes the build foundation: no Matrix client,
//! networking, authentication or session handling is implemented yet.

#[cfg(test)]
mod tests {
    use matrix_sdk::ruma::UserId;

    /// Smoke test: proves `matrix-sdk` resolves, links and its (offline)
    /// identifier types work as expected.
    #[test]
    fn matrix_sdk_parses_user_ids() {
        let user_id = UserId::parse("@alice:example.org").expect("valid Matrix user ID");

        assert_eq!(user_id.localpart(), "alice");
        assert_eq!(user_id.server_name(), "example.org");
        assert!(UserId::parse("alice").is_err());
    }
}

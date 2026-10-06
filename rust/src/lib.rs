//! Native core of the desktop messaging client.
//!
//! This crate hosts the Matrix integration (built on [`matrix_sdk`]) and will
//! later be exposed to the Flutter application through Flutter Rust Bridge.
//!
//! [`MessengerCore`] is the entry point: it is created for a homeserver and
//! owns the Matrix client used by all subsequent operations (authentication,
//! session persistence, room listing, text messages and continuous sync with
//! [`CoreEvent`]s).

mod error;
mod homeserver;
mod messages;
mod messenger_core;
mod realtime;
mod rooms;
mod storage;
#[cfg(test)]
mod test_support;

pub use error::CoreError;
pub use messages::{MAX_MESSAGES, Message, SentMessage};
pub use messenger_core::{LogoutOutcome, MessengerCore, RestoreOutcome};
pub use realtime::{CoreEvent, CoreEvents, SyncState};
pub use rooms::RoomSummary;

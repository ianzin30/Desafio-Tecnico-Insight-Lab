//! Native core of the desktop messaging client.
//!
//! This crate hosts the Matrix integration (built on [`matrix_sdk`]) and will
//! later be exposed to the Flutter application through Flutter Rust Bridge.
//!
//! [`MessengerCore`] is the entry point: it is created for a homeserver and
//! owns the Matrix client used by all subsequent operations. Authentication,
//! rooms, messages and sync are not implemented yet.

mod error;
mod homeserver;
mod messenger_core;

pub use error::CoreError;
pub use messenger_core::MessengerCore;

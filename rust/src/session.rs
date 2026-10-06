//! Match wrapper: participants, lifecycle, move log.
//!
//! Owns `Created -> SettingUp -> Ready -> Playing -> Finished`
//! and the signed, hash-linked match record (separate from the
//! position history chess rules need).

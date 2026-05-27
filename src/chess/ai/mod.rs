//! Chess AI opponents: evaluation and search.

pub(crate) mod eval;
mod search;

pub(crate) use search::find_best_move;

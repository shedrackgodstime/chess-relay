//! Strong chess value types with validated construction.
//!
//! `Square`, `Piece`, and `Move` are the vocabulary every later slice
//! (board, generation, game) shares. Invalid values are `Err`, never
//! panics, so callers above (session, bridge) stay crash-free.
//!
//! Oracles: prototype `ref/chess-relay/chess/move.gd`
//! (`{from:[x,y],to:[x,y],promotion}`) and `board_state.gd`
//! (`code = type*2+side+1`). Indexing here is `0..64`, `a1 == 0`,
//! which suits Rust iteration better than prototype `[x, y]` pairs.
//!
//! # Examples
//!
//! ```
//! use chess_relay_core::chess_core::{Move, Square};
//!
//! let mv: Move = "e2e4".parse()?;
//! assert_eq!(mv.from, Square::try_new(12)?); // e2
//! assert_eq!(mv.to, Square::try_new(28)?);   // e4
//! # Ok::<(), chess_relay_core::chess_core::IllegalMove>(())
//! ```

use std::backtrace::Backtrace;
use std::fmt::{self, Display, Formatter, Write as _};
use std::str::FromStr;

/// Side to move or piece colour.
///
/// # Examples
///
/// ```
/// use chess_relay_core::chess_core::Color;
///
/// assert_eq!(Color::White.opposite(), Color::Black);
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Color {
    /// First mover; ranks 1-2 at start.
    White,
    /// Second mover; ranks 7-8 at start.
    Black,
}

impl Color {
    /// Opposing side.
    #[must_use]
    pub fn opposite(self) -> Self {
        match self {
            Self::White => Self::Black,
            Self::Black => Self::White,
        }
    }
}

impl Display for Color {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::White => "white",
            Self::Black => "black",
        })
    }
}

/// Piece kind without colour.
///
/// Promotion targets exclude `Pawn` and `King`; `Move::new` enforces it.
///
/// # Examples
///
/// ```
/// use chess_relay_core::chess_core::Role;
///
/// assert_eq!(Role::from_char('n')?, Role::Knight);
/// # Ok::<(), chess_relay_core::chess_core::IllegalMove>(())
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Role {
    /// Moves forward, captures diagonally, promotes on last rank.
    Pawn,
    /// Jumps in L shapes.
    Knight,
    /// Slides diagonally.
    Bishop,
    /// Slides orthogonally.
    Rook,
    /// Slides diagonally and orthogonally.
    Queen,
    /// Moves one square; game ends when mated.
    King,
}

impl Role {
    /// Parses English piece letter (case-insensitive, `n` = knight).
    ///
    /// # Errors
    ///
    /// Returns [`IllegalMove`] when `c` names no piece.
    pub fn from_char(c: char) -> Result<Self, IllegalMove> {
        match c.to_ascii_lowercase() {
            'p' => Ok(Self::Pawn),
            'n' => Ok(Self::Knight),
            'b' => Ok(Self::Bishop),
            'r' => Ok(Self::Rook),
            'q' => Ok(Self::Queen),
            'k' => Ok(Self::King),
            _ => Err(IllegalMove::parse(format!("unknown piece letter '{c}'"))),
        }
    }

    /// English piece letter (`n` = knight).
    #[must_use]
    pub fn as_char(self) -> char {
        match self {
            Self::Pawn => 'p',
            Self::Knight => 'n',
            Self::Bishop => 'b',
            Self::Rook => 'r',
            Self::Queen => 'q',
            Self::King => 'k',
        }
    }
}

impl Display for Role {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        f.write_char(self.as_char())
    }
}

/// Coloured piece on a square.
///
/// Any colour/role pair is legal; board occupancy is a later slice.
///
/// # Examples
///
/// ```
/// use chess_relay_core::chess_core::{Color, Piece, Role};
///
/// let piece = Piece::new(Color::White, Role::Knight);
/// assert_eq!(piece.to_string(), "N");
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Piece {
    /// Owning side.
    pub color: Color,
    /// Piece kind.
    pub role: Role,
}

impl Piece {
    /// Combines colour and kind.
    #[must_use]
    pub fn new(color: Color, role: Role) -> Self {
        Self { color, role }
    }
}

impl Display for Piece {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        let c = self.role.as_char();
        match self.color {
            Color::White => f.write_char(c.to_ascii_uppercase()),
            Color::Black => f.write_char(c),
        }
    }
}

/// Board square as validated `0..64` index.
///
/// `a1 == 0`, `h1 == 7`, `a8 == 56`, `h8 == 63`;
/// `index == rank * 8 + file`, files and ranks `0..8`.
///
/// # Examples
///
/// ```
/// use chess_relay_core::chess_core::Square;
///
/// let e4 = Square::from_xy(4, 3)?;
/// assert_eq!(e4.to_string(), "e4");
/// # Ok::<(), chess_relay_core::chess_core::IllegalMove>(())
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Square(u8);

impl Square {
    /// Highest valid index.
    pub const MAX_INDEX: u8 = 63;

    /// Wraps a raw index after range check.
    ///
    /// # Errors
    ///
    /// Returns [`IllegalMove`] when `index > 63`.
    pub fn try_new(index: u8) -> Result<Self, IllegalMove> {
        if index > Self::MAX_INDEX {
            return Err(IllegalMove::out_of_range(index));
        }
        Ok(Self(index))
    }

    /// Builds from `0..8` file (a-h) and rank (1-8) coordinates.
    ///
    /// # Errors
    ///
    /// Returns [`IllegalMove`] when either coordinate exceeds 7.
    pub fn from_xy(file: u8, rank: u8) -> Result<Self, IllegalMove> {
        if file > 7 {
            return Err(IllegalMove::out_of_range(file));
        }
        if rank > 7 {
            return Err(IllegalMove::out_of_range(rank));
        }
        Ok(Self(rank * 8 + file))
    }

    /// Raw `0..64` index.
    #[must_use]
    pub fn index(self) -> u8 {
        self.0
    }

    /// File `0..8` (a-h).
    #[must_use]
    pub fn file(self) -> u8 {
        self.0 % 8
    }

    /// Rank `0..8` (1-8).
    #[must_use]
    pub fn rank(self) -> u8 {
        self.0 / 8
    }
}

impl Display for Square {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        let file = (b'a' + self.file()) as char;
        let rank = (b'1' + self.rank()) as char;
        f.write_char(file)?;
        f.write_char(rank)
    }
}

impl FromStr for Square {
    type Err = IllegalMove;

    /// Parses algebraic notation (`"e4"`).
    ///
    /// # Errors
    ///
    /// Returns [`IllegalMove`] for malformed or off-board input.
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let bytes = s.as_bytes();
        if bytes.len() != 2 {
            return Err(IllegalMove::parse(format!("bad square '{s}'")));
        }
        let (file, rank) = (bytes[0], bytes[1]);
        if !(b'a'..=b'h').contains(&file) || !(b'1'..=b'8').contains(&rank) {
            return Err(IllegalMove::parse(format!("bad square '{s}'")));
        }
        // Bounds checked above; `from_xy` cannot fail here.
        Self::from_xy(file - b'a', rank - b'1')
            .map_err(|_| IllegalMove::parse(format!("bad square '{s}'")))
    }
}

/// Chess move between validated squares.
///
/// Legality against a position belongs to a later slice; this type only
/// rejects structurally void moves (no-op, impossible promotion piece).
/// UCI rendering (`"e2e4"`, `"e7e8q"`) doubles as the future wire form.
///
/// # Examples
///
/// ```
/// use chess_relay_core::chess_core::{Move, Role, Square};
///
/// let from = Square::try_new(52)?; // e7
/// let to = Square::try_new(60)?;   // e8
/// let mv = Move::new(from, to, Some(Role::Queen))?;
/// assert_eq!(mv.to_string(), "e7e8q");
/// # Ok::<(), chess_relay_core::chess_core::IllegalMove>(())
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Move {
    /// Departure square.
    pub from: Square,
    /// Arrival square.
    pub to: Square,
    /// Promotion target, if the move promotes.
    pub promotion: Option<Role>,
}

impl Move {
    /// Builds a move, rejecting void structure.
    ///
    /// # Errors
    ///
    /// Returns [`IllegalMove`] when `from == to`, or when `promotion`
    /// names [`Role::Pawn`] or [`Role::King`].
    pub fn new(from: Square, to: Square, promotion: Option<Role>) -> Result<Self, IllegalMove> {
        if from == to {
            return Err(IllegalMove::same_square());
        }
        if matches!(promotion, Some(Role::Pawn | Role::King)) {
            return Err(IllegalMove::invalid_promotion(
                promotion.map(Role::as_char).unwrap_or('?'),
            ));
        }
        Ok(Self {
            from,
            to,
            promotion,
        })
    }

    /// Whether the move promotes.
    #[must_use]
    pub fn is_promotion(self) -> bool {
        self.promotion.is_some()
    }
}

impl Display for Move {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        self.from.fmt(f)?;
        self.to.fmt(f)?;
        if let Some(role) = self.promotion {
            f.write_char(role.as_char())?;
        }
        Ok(())
    }
}

impl FromStr for Move {
    type Err = IllegalMove;

    /// Parses UCI (`"e2e4"`, `"e7e8q"`).
    ///
    /// # Errors
    ///
    /// Returns [`IllegalMove`] for malformed text or void structure.
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let bytes = s.as_bytes();
        if bytes.len() != 4 && bytes.len() != 5 {
            return Err(IllegalMove::parse(format!("bad move '{s}'")));
        }
        let from: Square = s[0..2].parse()?;
        let to: Square = s[2..4].parse()?;
        let promotion = if bytes.len() == 5 {
            Some(Role::from_char(bytes[4] as char)?)
        } else {
            None
        };
        Self::new(from, to, promotion)
    }
}

/// Chess-core failure: structurally void input or illegal move.
///
/// Sole error type of this layer (arch doc §Errors). Carries a private
/// kind plus a captured backtrace; callers match via `is_*` predicates
/// instead of an exposed enum.
///
/// # Examples
///
/// ```
/// use chess_relay_core::chess_core::{IllegalMove, Square};
///
/// let err = Square::try_new(64).unwrap_err();
/// assert!(err.is_out_of_range());
/// ```
#[derive(Debug)]
pub struct IllegalMove {
    kind: IllegalMoveKind,
    backtrace: Backtrace,
}

#[derive(Debug)]
pub(crate) enum IllegalMoveKind {
    /// Index or coordinate outside the board.
    OutOfRange { value: u8 },
    /// Departure equals arrival.
    SameSquare,
    /// Promotion to pawn/king, or unknown promotion letter.
    InvalidPromotion { role: char },
    /// Unparseable text, with the offending input.
    Parse { input: String },
}

impl IllegalMove {
    pub(crate) fn out_of_range(value: u8) -> Self {
        Self {
            kind: IllegalMoveKind::OutOfRange { value },
            backtrace: Backtrace::capture(),
        }
    }

    pub(crate) fn same_square() -> Self {
        Self {
            kind: IllegalMoveKind::SameSquare,
            backtrace: Backtrace::capture(),
        }
    }

    pub(crate) fn invalid_promotion(role: char) -> Self {
        Self {
            kind: IllegalMoveKind::InvalidPromotion { role },
            backtrace: Backtrace::capture(),
        }
    }

    pub(crate) fn parse(input: String) -> Self {
        Self {
            kind: IllegalMoveKind::Parse { input },
            backtrace: Backtrace::capture(),
        }
    }

    /// Whether a board index or coordinate was off-board.
    #[must_use]
    pub fn is_out_of_range(&self) -> bool {
        matches!(self.kind, IllegalMoveKind::OutOfRange { .. })
    }

    /// Whether departure equalled arrival.
    #[must_use]
    pub fn is_same_square(&self) -> bool {
        matches!(self.kind, IllegalMoveKind::SameSquare)
    }

    /// Whether promotion named an impossible piece.
    #[must_use]
    pub fn is_invalid_promotion(&self) -> bool {
        matches!(self.kind, IllegalMoveKind::InvalidPromotion { .. })
    }

    /// Whether text failed to parse.
    #[must_use]
    pub fn is_parse(&self) -> bool {
        matches!(self.kind, IllegalMoveKind::Parse { .. })
    }
}

impl Display for IllegalMove {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match &self.kind {
            IllegalMoveKind::OutOfRange { value } => {
                write!(f, "illegal move: value {value} is off the board")
            }
            IllegalMoveKind::SameSquare => {
                write!(f, "illegal move: departure equals arrival")
            }
            IllegalMoveKind::InvalidPromotion { role } => {
                write!(f, "illegal move: cannot promote to '{role}'")
            }
            IllegalMoveKind::Parse { input } => {
                write!(f, "illegal move: cannot parse '{input}'")
            }
        }?;
        use std::backtrace::BacktraceStatus::Captured;
        if self.backtrace.status() == Captured {
            write!(f, "\n{}", self.backtrace)?;
        }
        Ok(())
    }
}

impl std::error::Error for IllegalMove {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn square_index_covers_all_corners() {
        assert_eq!(Square::try_new(0).unwrap().to_string(), "a1");
        assert_eq!(Square::try_new(7).unwrap().to_string(), "h1");
        assert_eq!(Square::try_new(56).unwrap().to_string(), "a8");
        assert_eq!(Square::try_new(63).unwrap().to_string(), "h8");
    }

    #[test]
    fn square_rejects_off_board() {
        for bad in [64, 100, 255] {
            let err = Square::try_new(bad).unwrap_err();
            assert!(err.is_out_of_range(), "index {bad}");
        }
        assert!(Square::from_xy(8, 0).unwrap_err().is_out_of_range());
        assert!(Square::from_xy(0, 8).unwrap_err().is_out_of_range());
    }

    #[test]
    fn square_names_round_trip() {
        for name in ["a1", "e4", "h8", "d5"] {
            let sq: Square = name.parse().unwrap();
            assert_eq!(sq.to_string(), name);
        }
        for bad in ["", "e", "e44", "i1", "e9", "E4"] {
            assert!(bad.parse::<Square>().is_err(), "input '{bad}'");
        }
    }

    #[test]
    fn move_uci_round_trip_with_promotion() {
        for uci in ["e2e4", "g1f3", "e7e8q", "a7a8n", "h2h1r", "c7c8b"] {
            let mv: Move = uci.parse().unwrap();
            assert_eq!(mv.to_string(), uci);
        }
        assert!("e7e8q".parse::<Move>().unwrap().is_promotion());
        assert!(!"e2e4".parse::<Move>().unwrap().is_promotion());
    }

    #[test]
    fn move_rejects_void_structure() {
        let e4 = Square::try_new(28).unwrap();
        assert!("e4e4".parse::<Move>().unwrap_err().is_same_square());
        assert!(Move::new(e4, e4, None).unwrap_err().is_same_square());
        assert!("e7e8p".parse::<Move>().unwrap_err().is_invalid_promotion());
        assert!("e7e8k".parse::<Move>().unwrap_err().is_invalid_promotion());
        for bad in ["", "e2", "e2e4qz", "e2e9", "zzzz"] {
            assert!(bad.parse::<Move>().is_err(), "input '{bad}'");
        }
    }

    #[test]
    fn piece_letters_distinguish_sides() {
        let white = Piece::new(Color::White, Role::Knight).to_string();
        let black = Piece::new(Color::Black, Role::Knight).to_string();
        assert_eq!((white.as_str(), black.as_str()), ("N", "n"));
        assert_eq!(Color::White.opposite().to_string(), "black");
    }

    #[test]
    fn error_display_names_the_problem() {
        let text = Square::try_new(64).unwrap_err().to_string();
        assert!(text.contains("off the board"), "{text}");
    }
}

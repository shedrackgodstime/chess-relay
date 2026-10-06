//! Board representation and FEN serialization.
//!
//! A `Board` holds the four positional FEN fields: piece placement,
//! side to move, castling rights, and en-passant square. The two
//! counters travel alongside as plain data so FEN round-trips losslessly;
//! their move-counting meaning belongs to the game slice, not here.
//!
//! Structural checks in [`Board::from_fen`] reject void positions
//! (wrong shape, missing kings, pawns on back ranks, impossible
//! en-passant rank). Deeper context checks (kings in check from both
//! sides, en-passant pawn actually present) belong to game setup.
//!
//! Oracles: prototype `ref/chess-relay/chess/board_state.gd`
//! (`to_fen`/`from_fen`, 4 fields) and `ref/shakmaty` FEN vectors.
//!
//! # Examples
//!
//! ```
//! use chess_relay_core::chess_core::Board;
//!
//! let board = Board::startpos();
//! assert_eq!(board.to_fen(), Board::STARTPOS_FEN);
//! # Ok::<(), chess_relay_core::chess_core::IllegalMove>(())
//! ```

use super::types::{Color, IllegalMove, Piece, Role, Square};
use std::fmt::Write as _;

/// Castling availability as a validated bit set.
///
/// Renders in FEN order `KQkq`, or `-` when empty.
///
/// # Examples
///
/// ```
/// use chess_relay_core::chess_core::CastlingRights;
///
/// let rights: CastlingRights = "Kq".parse()?;
/// assert!(rights.has(CastlingRights::WHITE_KINGSIDE));
/// assert!(!rights.has(CastlingRights::WHITE_QUEENSIDE));
/// # Ok::<(), chess_relay_core::chess_core::IllegalMove>(())
/// ```
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct CastlingRights(u8);

impl CastlingRights {
    /// White may castle kingside.
    pub const WHITE_KINGSIDE: Self = Self(0b0001);
    /// White may castle queenside.
    pub const WHITE_QUEENSIDE: Self = Self(0b0010);
    /// Black may castle kingside.
    pub const BLACK_KINGSIDE: Self = Self(0b0100);
    /// Black may castle queenside.
    pub const BLACK_QUEENSIDE: Self = Self(0b1000);
    /// No castling available.
    pub const NONE: Self = Self(0);
    /// All castling available.
    pub const ALL: Self = Self(0b1111);

    /// Whether `flag` is set.
    #[must_use]
    pub fn has(self, flag: Self) -> bool {
        self.0 & flag.0 != 0
    }

    /// Sets `flag`.
    pub fn insert(&mut self, flag: Self) {
        self.0 |= flag.0;
    }

    /// Clears `flag`.
    pub fn remove(&mut self, flag: Self) {
        self.0 &= !flag.0;
    }

    /// Whether no castling is available.
    #[must_use]
    pub fn is_empty(self) -> bool {
        self.0 == 0
    }

    fn from_char(c: char) -> Result<Self, IllegalMove> {
        match c {
            'K' => Ok(Self::WHITE_KINGSIDE),
            'Q' => Ok(Self::WHITE_QUEENSIDE),
            'k' => Ok(Self::BLACK_KINGSIDE),
            'q' => Ok(Self::BLACK_QUEENSIDE),
            _ => Err(IllegalMove::parse(format!("bad castling '{c}'"))),
        }
    }
}

impl std::fmt::Display for CastlingRights {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if self.is_empty() {
            return f.write_str("-");
        }
        for (flag, c) in [
            (Self::WHITE_KINGSIDE, 'K'),
            (Self::WHITE_QUEENSIDE, 'Q'),
            (Self::BLACK_KINGSIDE, 'k'),
            (Self::BLACK_QUEENSIDE, 'q'),
        ] {
            if self.has(flag) {
                f.write_char(c)?;
            }
        }
        Ok(())
    }
}

impl std::str::FromStr for CastlingRights {
    type Err = IllegalMove;

    /// Parses the FEN castling field (`"KQkq"` or `"-"`).
    ///
    /// # Errors
    ///
    /// Returns [`IllegalMove`] on unknown or duplicated letters.
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        if s == "-" {
            return Ok(Self::NONE);
        }
        if s.is_empty() || s.len() > 4 {
            return Err(IllegalMove::parse(format!("bad castling '{s}'")));
        }
        let mut rights = Self::NONE;
        for c in s.chars() {
            let flag = Self::from_char(c)?;
            if rights.has(flag) {
                return Err(IllegalMove::parse(format!("bad castling '{s}'")));
            }
            rights.insert(flag);
        }
        Ok(rights)
    }
}

/// Chess position: pieces, turn, castling, en passant, counters.
///
/// `Copy` so search and simulation copy positions freely; repetition
/// tables in the game slice key on owned values.
///
/// # Examples
///
/// ```
/// use chess_relay_core::chess_core::Board;
///
/// let board = Board::startpos();
/// assert_eq!(board.to_fen(), Board::STARTPOS_FEN);
/// # Ok::<(), chess_relay_core::chess_core::IllegalMove>(())
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Board {
    squares: [Option<Piece>; 64],
    side_to_move: Color,
    castling: CastlingRights,
    en_passant: Option<Square>,
    halfmove_clock: u32,
    fullmove_number: u32,
}

impl Board {
    /// Standard initial position in FEN.
    pub const STARTPOS_FEN: &'static str =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

    /// Standard initial position.
    #[must_use]
    pub fn startpos() -> Self {
        Self::from_fen(Self::STARTPOS_FEN).expect("STARTPOS_FEN is valid")
    }

    /// Empty board, White to move, no rights, counters reset.
    ///
    /// Setup helper for tests and later slices; place pieces with
    /// [`Board::place`].
    #[must_use]
    pub fn empty() -> Self {
        Self {
            squares: [None; 64],
            side_to_move: Color::White,
            castling: CastlingRights::NONE,
            en_passant: None,
            halfmove_clock: 0,
            fullmove_number: 1,
        }
    }

    /// Puts `piece` on `square`, replacing any occupant.
    pub fn place(&mut self, piece: Piece, square: Square) {
        self.squares[square.index() as usize] = Some(piece);
    }

    /// Piece on `square`, if any.
    #[must_use]
    pub fn piece_at(&self, square: Square) -> Option<Piece> {
        self.squares[square.index() as usize]
    }

    /// Side to move.
    #[must_use]
    pub fn side_to_move(&self) -> Color {
        self.side_to_move
    }

    /// Current castling rights.
    #[must_use]
    pub fn castling(&self) -> CastlingRights {
        self.castling
    }

    /// En-passant target square, if any.
    #[must_use]
    pub fn en_passant(&self) -> Option<Square> {
        self.en_passant
    }

    /// Halfmove clock (counter data; meaning lives in game slice).
    #[must_use]
    pub fn halfmove_clock(&self) -> u32 {
        self.halfmove_clock
    }

    /// Fullmove number, starting at 1 (counter data; see above).
    #[must_use]
    pub fn fullmove_number(&self) -> u32 {
        self.fullmove_number
    }

    /// Renders full six-field FEN.
    #[must_use]
    pub fn to_fen(&self) -> String {
        let mut placement = String::with_capacity(64 + 7);
        for rank in (0..8).rev() {
            if rank != 7 {
                placement.push('/');
            }
            let mut empties = 0;
            for file in 0..8 {
                // `from_xy` cannot fail: coordinates are in range.
                let sq = Square::from_xy(file, rank).expect("board coordinates are valid");
                match self.piece_at(sq) {
                    Some(piece) => {
                        if empties > 0 {
                            placement.push((b'0' + empties) as char);
                            empties = 0;
                        }
                        placement.push(piece_fen_char(piece));
                    }
                    None => empties += 1,
                }
            }
            if empties > 0 {
                placement.push((b'0' + empties) as char);
            }
        }
        let side = match self.side_to_move {
            Color::White => "w",
            Color::Black => "b",
        };
        let ep = self
            .en_passant
            .map_or_else(|| "-".to_string(), |sq| sq.to_string());
        format!(
            "{placement} {side} {} {ep} {} {}",
            self.castling, self.halfmove_clock, self.fullmove_number
        )
    }

    /// Parses and structurally validates six-field FEN.
    ///
    /// # Errors
    ///
    /// Returns [`IllegalMove`] on malformed fields, missing kings,
    /// back-rank pawns, or impossible en-passant ranks.
    pub fn from_fen(fen: &str) -> Result<Self, IllegalMove> {
        let fields: Vec<&str> = fen.split_whitespace().collect();
        if fields.len() != 6 {
            return Err(IllegalMove::parse(format!("bad FEN '{fen}'")));
        }
        let [placement, side, castling, en_passant, halfmove, fullmove] = fields.as_slice() else {
            return Err(IllegalMove::parse(format!("bad FEN '{fen}'")));
        };

        let mut board = Self::empty();
        parse_placement(&mut board, placement, fen)?;
        validate_kings(&board, fen)?;

        board.side_to_move = match *side {
            "w" => Color::White,
            "b" => Color::Black,
            _ => return Err(IllegalMove::parse(format!("bad FEN '{fen}'"))),
        };
        board.castling = castling.parse()?;
        board.en_passant = match *en_passant {
            "-" => None,
            text => {
                let sq: Square = text
                    .parse()
                    .map_err(|_| IllegalMove::parse(format!("bad FEN '{fen}'")))?;
                if sq.rank() != 2 && sq.rank() != 5 {
                    return Err(IllegalMove::parse(format!("bad FEN '{fen}'")));
                }
                Some(sq)
            }
        };
        board.halfmove_clock = halfmove
            .parse()
            .map_err(|_| IllegalMove::parse(format!("bad FEN '{fen}'")))?;
        board.fullmove_number = fullmove
            .parse()
            .map_err(|_| IllegalMove::parse(format!("bad FEN '{fen}'")))?;
        if board.fullmove_number < 1 {
            return Err(IllegalMove::parse(format!("bad FEN '{fen}'")));
        }
        Ok(board)
    }
}

impl std::fmt::Display for Board {
    /// Renders FEN (the user-facing position serialization).
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.to_fen())
    }
}

impl std::str::FromStr for Board {
    type Err = IllegalMove;

    /// Parses FEN; see [`Board::from_fen`].
    ///
    /// # Errors
    ///
    /// Returns [`IllegalMove`] on malformed or void positions.
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Self::from_fen(s)
    }
}

fn piece_fen_char(piece: Piece) -> char {
    let c = piece.role.as_char();
    match piece.color {
        Color::White => c.to_ascii_uppercase(),
        Color::Black => c,
    }
}

fn parse_placement(board: &mut Board, placement: &str, fen: &str) -> Result<(), IllegalMove> {
    let ranks: Vec<&str> = placement.split('/').collect();
    if ranks.len() != 8 {
        return Err(IllegalMove::parse(format!("bad FEN '{fen}'")));
    }
    for (rank_from_top, rank_text) in ranks.iter().enumerate() {
        // FEN lists rank 8 first; rank index 0 is rank 1.
        let rank = 7 - rank_from_top as u8;
        let mut file: u8 = 0;
        if rank_text.is_empty() {
            return Err(IllegalMove::parse(format!("bad FEN '{fen}'")));
        }
        for c in rank_text.chars() {
            if let Some(digit) = c.to_digit(10) {
                if !(1..=8).contains(&digit) {
                    return Err(IllegalMove::parse(format!("bad FEN '{fen}'")));
                }
                file += digit as u8;
            } else {
                let role = Role::from_char(c)
                    .map_err(|_| IllegalMove::parse(format!("bad FEN '{fen}'")))?;
                let color = if c.is_ascii_uppercase() {
                    Color::White
                } else {
                    Color::Black
                };
                if role == Role::Pawn && (rank == 0 || rank == 7) {
                    return Err(IllegalMove::parse(format!("bad FEN '{fen}'")));
                }
                if file >= 8 {
                    return Err(IllegalMove::parse(format!("bad FEN '{fen}'")));
                }
                // Coordinates checked above; cannot fail.
                let sq = Square::from_xy(file, rank).expect("FEN coordinates are valid");
                board.place(Piece::new(color, role), sq);
                file += 1;
            }
            if file > 8 {
                return Err(IllegalMove::parse(format!("bad FEN '{fen}'")));
            }
        }
        if file != 8 {
            return Err(IllegalMove::parse(format!("bad FEN '{fen}'")));
        }
    }
    Ok(())
}

fn validate_kings(board: &Board, fen: &str) -> Result<(), IllegalMove> {
    let mut white = 0;
    let mut black = 0;
    for index in 0..64 {
        // Index range is valid by construction.
        let sq = Square::try_new(index).expect("square index is valid");
        match board.piece_at(sq) {
            Some(Piece {
                color: Color::White,
                role: Role::King,
            }) => white += 1,
            Some(Piece {
                color: Color::Black,
                role: Role::King,
            }) => black += 1,
            _ => {}
        }
    }
    if white != 1 || black != 1 {
        return Err(IllegalMove::parse(format!("bad FEN '{fen}'")));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn startpos_renders_canonical_fen() {
        assert_eq!(Board::startpos().to_fen(), Board::STARTPOS_FEN);
    }

    #[test]
    fn known_positions_round_trip() {
        for fen in [
            Board::STARTPOS_FEN,
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
            "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
        ] {
            let board = Board::from_fen(fen).unwrap();
            assert_eq!(board.to_fen(), fen, "round-trip");
        }
    }

    #[test]
    fn en_passant_accepts_only_third_and_sixth_ranks() {
        for fen in [
            "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
            "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2",
        ] {
            assert!(Board::from_fen(fen).is_ok(), "{fen}");
        }
        let bad = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq e4 0 1";
        assert!(Board::from_fen(bad).is_err());
    }

    #[test]
    fn void_positions_rejected() {
        for bad in [
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0", // 5 fields
            "rnbqkbnr/pppppppp/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", // 7 ranks
            "rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", // rank of 9
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNX w KQkq - 0 1", // bad piece
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1", // bad side
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KK - 0 1", // dup castling
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - x 1", // bad clock
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 0", // fullmove 0
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBN w KQkq - 0 1", // white kingless
            "Pnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", // pawn on rank 8
        ] {
            assert!(Board::from_fen(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn castling_rights_round_trip() {
        for text in ["-", "K", "q", "KQkq", "kq", "KQ"] {
            let rights: CastlingRights = text.parse().unwrap();
            assert_eq!(rights.to_string(), text);
        }
        assert!("KK".parse::<CastlingRights>().is_err());
        assert!("X".parse::<CastlingRights>().is_err());
    }

    #[test]
    fn empty_board_takes_setup_pieces() {
        let mut board = Board::empty();
        let e4 = Square::try_new(28).unwrap();
        board.place(Piece::new(Color::White, Role::King), e4);
        assert_eq!(
            board.piece_at(e4),
            Some(Piece::new(Color::White, Role::King))
        );
        assert_eq!(board.side_to_move(), Color::White);
    }
}

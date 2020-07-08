import Array "mo:base/Array";
import Int "mo:base/Int";
import Iter "mo:base/Iter";


module {

  // Color of a piece is either black or white.
  public type Color = { #black; #white; };
  
  public let empty_piece : ?Color = null;
  public let white_piece : ?Color = ?(#white);
  public let black_piece : ?Color = ?(#black);

   // Board is a NxN array with either empty cells, or a Color piece.
  public type Board = [var ?Color];
  
  // At the end of game, we count how many pieces are left on the board for
  // each color.
  public type ColorCount = {
    white: Nat;
    black: Nat;
  };

  // Result of placing a new piece
  public type Result = {
    #InvalidCoordinate;
    #IllegalMove;
    #Pass;
    #OK;
    #GameOver: ColorCount;
  };

  // Initialize a game board with initial black & white pieces, and empty otherwise.
  public func init_board(N: Nat, board: Board, blacks: [(Nat, Nat)], whites: [(Nat, Nat)]) {
    for (i in Iter.range(0, N * N - 1)) {
         board[i] := empty_piece; 
    };
    for ((i, j) in blacks.vals()) {
      board[i * N + j] := black_piece;
    };
    for ((i, j) in whites.vals()) {
      board[i * N + j] := white_piece;
    };
  };

  // Render the board into a string
  public func render_board(N: Nat, board: Board) : Text {
      var str = "";
      for (i in Iter.range(0, N-1)) {
        for (j in Iter.range(0, N-1)) {
          switch (board[i * N + j]) {
            case null { str := str # "."; };
            case (?#white) { str := str # "O"; };
            case (?#black) { str := str # "*"; };
          };
        };
      };
      str
  };

  // Given a color, return its opponent color
  public func opponent(color: Color): Color {
      switch (color) {
        case (#black) #white;
        case (#white) #black;
      }
  };

  // Check if two ?Color value are the same.
  public func match_color(a: ?Color, b: ?Color) : Bool {
    switch (a, b) {
      case (null, null) true;
      case (?#black, ?#black) true;
      case (?#white, ?#white) true;
      case _ false;
    }
  };

  // Check if a piece of the given color exists on the board using
  // coordinate (i, j) and offset (p, q).
  func exists(N: Nat, board: Board, color: Color, i: Nat, j: Nat, p:Int, q:Int) : Bool {
    let s = i + p;
    let t = j + q;
    s >= 0 and s < N and t >= 0 and t < N and match_color(board[Int.abs (s * N + t)], ?color)
  };

  // Check if a piece of the given color eventually exits on the board
  // using coordinate (i, j) and direction (p, q), ignoring opponent colors
  // in between. Return false if the given color is not found before reaching
  // empty cell or board boundary.
  func eventually(N: Nat, board: Board, color: Color, i: Nat, j: Nat, p:Int, q:Int) : Bool {
    if (exists(N, board, opponent(color),  i, j, p, q)) {
      // the abs below is safe because its precondition is already checked
      eventually(N, board, color, Int.abs(i + p), Int.abs(j + q), p, q)
    } else {
      exists(N, board, color, i, j, p, q)
    }
  };

  // Flip pieces of opponent color into the given color starting from
  // coordinate (i, j) and along direction (p, q).
  func flip(N: Nat, board: Board, color: Color, i: Nat, j: Nat, p:Int, q:Int) {
    if (exists(N, board, opponent(color), i, j, p, q)) {
      // the abs below is safe because its precondition is already checked
      let s = Int.abs(i + p);
      let t = Int.abs(j + q);
      board[s * N + t] := ?color;
      flip(N, board, color, s, t, p, q);
    }
  };

  // Return true if a valid move is possible for color at the given position (i, j).
  // The precondition is that (i, j) is empty.
  func valid_move(N: Nat, board: Board, color: Color, i: Nat, j: Nat) : Bool {
      for (p in [-1, 0, 1].vals()) {
        for (q in [-1, 0, 1].vals()) {
          if (not(p == 0 and q == 0)) {
            if (exists(N, board, opponent(color), i, j, p, q) and 
                eventually(N, board, color, i, j, p, q)) {
              return true;
            }
          }
        }
      };
      return false;
  };

  // Calculate all validate positions for a given color by returning
  // a board that has the cells colored.
  func valid_moves(N: Nat, board: Board, color: Color) : Board {
      let next : Board = Array.init<?Color>(N * N, empty_piece);
      for (i in Iter.range(0, N-1)) {
        for (j in Iter.range(0, N-1)) {
          if (match_color(board[i * N + j], empty_piece) and valid_move(N, board, color, i, j)) {
            next[i * N + j] := ?color;
          }
        }
      };
      next 
  };

  // Set a piece on the board at a given position, and flip all
  // affected opponent pieces accordingly. It requires that the
  // given position is a valid move before this call.
  func set_and_flip(N: Nat, board: Board, color: Color, i: Nat, j: Nat) {
      board[i * N + j] := ?color;
      for (p in [-1, 0, 1].vals()) {
        for (q in [-1, 0, 1].vals()) {
          if (not(p == 0 and q == 0)) {
            if (exists(N, board, opponent(color), i, j, p, q) and 
                eventually(N, board, color, i, j, p, q)) {
              flip(N, board, color, i, j, p, q);
            }
          }
        }
      }
  };

  // Check if the given board is empty.
  func is_empty(board: Board) : Bool {
    for (c in board.vals()) {
      if (not match_color(c, empty_piece)) {
        return false;
      }
    };
    true
  };

  // Return the white and black counts.
  func count(board: Board) : (Nat, Nat) {
    var wc = 0;
    var bc = 0;
    for (c in board.vals()) {
      switch (c) {
        case (?#white) { wc += 1; };
        case (?#black) { bc += 1; };
        case _ {};
      }
    };
    (wc, bc)
  };

  public func place(N: Nat, board: Board, color: Color, row: Nat, col: Nat) : Result {
    // Check input validity
    if (row >= N or col >= N) {
      return (#InvalidCoordinate);
    };

    var possible = valid_moves(N, board, color);
    if (not match_color(possible[row * N + col], empty_piece)) {
      set_and_flip(N, board, color, row, col);
      
      // if opponent can't make a move, either pass or end game.
      possible := valid_moves(N, board, opponent(color));
      if (is_empty(possible)) {
        possible := valid_moves(N, board, color);
        if (is_empty(possible)) {
          // when opponent also has no possible move, end game
          let (wc, bc) = count(board);
          #GameOver({ white = wc; black = bc; })
        } else {
          #Pass
        }
      } else {
        #OK
      }
    } else {
      #IllegalMove
    }
  }
}

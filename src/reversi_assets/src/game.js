//////////////////////////////////////////////////////////////////////////////
// Game logic (Copied from Motoko code)
// We use '*' for black and 'O' for white.
//////////////////////////////////////////////////////////////////////////////

// Return the opponent color.
function opponent(color) {
  return color == "*" ? "O" : "*";
}

// Check if a piece of the given color exists on the board using
// coordinate (i, j) and offset (p, q).
function exists(N, board, color, i, j, p, q) {
  let s = i + p;
  let t = j + q;
  return s >= 0 && s < N && t >= 0 && t < N && board[s * N + t] == color;
}

// Check if a piece of the given color eventually exits on the board
// using coordinate (i, j) and direction (p, q), ignoring opponent colors
// in between. Return false if the given color is not found before reaching
// empty cell or board boundary.
function eventually(N, board, color, i, j, p, q) {
  if (exists(N, board, opponent(color), i, j, p, q)) {
    return eventually(N, board, color, i + p, j + q, p, q);
  } else {
    return exists(N, board, color, i, j, p, q);
  }
}

// Return true if a valid move is possible for color at the given position (i, j).
export function valid_move(N, board, color, i, j) {
  for (var p = -1; p <= 1; p++) {
    for (var q = -1; q <= 1; q++) {
      if (!(p == 0 && q == 0)) {
        if (
          exists(N, board, opponent(color), i, j, p, q) &&
          eventually(N, board, color, i, j, p, q)
        ) {
          return true;
        }
      }
    }
  }
  return false;
}

// Calculate the number of validate next move for a given color.
function valid_moves(N, board, color) {
  var count = 0;
  for (var p = -1; p <= 1; p++) {
    for (var q = -1; q <= 1; q++) {
      if (board[i * N + j] == "." && valid_move(N, board, color, i, j)) {
        count += 1;
      }
    }
  }
  return count;
}

// Flip pieces of opponent color into the given color starting from
// coordinate (i, j) and along direction (p, q).
function flip(N, board, color, i, j, p, q) {
  if (exists(N, board, opponent(color), i, j, p, q)) {
    let s = i + p;
    let t = j + q;
    board[s * N + t] = color;
    flip(N, board, color, s, t, p, q);
  }
}

// Set a piece on the board at a given position, and flip all
// affected opponent pieces accordingly. It requires that the
// given position is a valid move before this call.
export function set_and_flip(N, board, color, i, j) {
  board[i * N + j] = color;
  for (var p = -1; p <= 1; p++) {
    for (var q = -1; q <= 1; q++) {
      if (!(p == 0 && q == 0)) {
        if (
          exists(N, board, opponent(color), i, j, p, q) &&
          eventually(N, board, color, i, j, p, q)
        ) {
          flip(N, board, color, i, j, p, q);
        }
      }
    }
  }
  return board;
}

// Given a sequence of moves, replay the board.
export function replay(N, moves) {
  var board = new Array(N * N);
  for (var i = 0; i < N * N; i++) {
    board[i] = ".";
  }
  var color = "O";
  for (var k = 0; k < moves.length; k++) {
    const idx = moves[k];
    const i = Math.floor(idx / N);
    const j = idx % N;
    if (k < 4) {
      board[idx] = color;
    } else if (valid_move(N, board, color, i, j)) {
      set_and_flip(N, board, color, i, j);
    } else {
      color = opponent(color);
      set_and_flip(N, board, color, i, j);
    }
    color = opponent(color);
  }
  return board;
}

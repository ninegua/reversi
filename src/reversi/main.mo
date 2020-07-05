import Array "mo:base/Array";
import Text "mo:base/Text";
import Iter "mo:base/Iter";
import Int "mo:base/Int";
import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Option "mo:base/Option";
import HashMap "mo:base/HashMap";
import Buf "mo:base/Buf";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Prim "mo:prim";

type PlayerId = Principal;
type PlayerName = Text;

type GameResult = {
  white: Nat;
  black: Nat;
};

type MoveResult = {
  #GameNotFound;
  #GameNotStarted;
  #InvalidCoordinate;
  #InvalidColor;
  #IllegalMove;
  #IllegalColor;
  #GameOver: GameResult;
  #Pass;
  #OK;
};

// Color related type and constants
type Color = { #black; #white; };
let empty : ?Color = null;
let white : ?Color = ?(#black);
let black : ?Color = ?(#white);

type Board = [var ?Color];

type PlayerState = {
  name: PlayerName;
  var score: Nat;
};

type PlayerView = {
  name: PlayerName;
  score: Nat;
};

type Players = {
  id_map: HashMap.HashMap<PlayerId, PlayerState>;
  name_map: HashMap.HashMap<PlayerName, PlayerId>;
};

type RegistrationError = {
  #InvalidName;
  #NameAlreadyExists;
};

// History of valid moves. The use of Nat8 here implies the max dimension is 8.
type Moves = Buf.Buf<Nat8>;

type GameState = {
  dimension: Nat;
  board: Board;
  moves: Moves;
  var black: (?PlayerId, PlayerName);
  var white: (?PlayerId, PlayerName);
  var next: Color;
  var result: ?GameResult;
}; 

type GameView = {
  dimension: Nat;
  board: Text;
  black: (?(), PlayerName);
  white: (?(), PlayerName);
  next: Color;
  result: ?GameResult;
};

type Games = Buf.Buf<GameState>;

type StartError = {
  #InvalidOpponentName;
  #PlayerNotFound;
};

actor {

  // Player database
  let players : Players = {
    id_map = HashMap.HashMap<PlayerId, PlayerState>(10, func (x, y) { x == y }, Principal.hash);
    name_map = HashMap.HashMap<PlayerName, PlayerId>(10, func (x, y) { x == y }, Text.hash);
  };

  func lookup_player_by_id(id: PlayerId) : ?PlayerState {
    players.id_map.get(id)
  };

  func lookup_id_by_name(name: PlayerName) : ?PlayerId {
    players.name_map.get(to_lowercase(name))
  };

  func insert_new_player(id: PlayerId, name_: PlayerName) : PlayerState {
    let player = { name = name_; var score = 0; };
    players.id_map.put(id, player);
    players.name_map.put(to_lowercase(name_), id);
    player
  };

  // Player login/registration. If the caller is not already found in the player database,
  // a new account is created with the given name. Otherwise the given name is ignored.
  // Return player info if the player is found or successfully registered, or an registration
  // error.
  public shared(msg) func register(name: Text): async Result.Result<PlayerView, RegistrationError> {
    let id = msg.caller;
    switch (lookup_player_by_id(id), valid_name(name)) {
      case (?player, _) {
        #ok({ name = player.name; score = player.score; })
      };
      case (_, false) (#err(#InvalidName));
      case (null, true) {
        switch (lookup_id_by_name(name)) {
          case null {
              let player = insert_new_player(id, name);
              #ok({ name = player.name; score = player.score; })
          };
          case (?_) (#err(#NameAlreadyExists));
        }
      }
    }
  };

  // convert text to lower_case
  func to_lowercase(name: Text) : Text {
    var str = "";
    for (c in Text.toIter(name)) {
      let ch = if ('A' <= c and c <= 'Z') { Prim.word32ToChar(Prim.charToWord32(c) + 32) } else { c };
      str := str # Prim.charToText(ch);
    };
    str 
  };

  func eq_nocase(s: Text, t: Text) : Bool {
    let m = s.size();
    let n = t.size();
    m == n and to_lowercase(s) == to_lowercase(t)
  };

  // check if player name is valid.
  func valid_name(name: Text): Bool {
    let str : [Char] = Iter.toArray(Text.toIter(name));
    if (str.size() < 3 or str.size() > 10) {
      return false;
    };
    for (i in Iter.range(0, str.size() - 1)) {
      let c = str[i];
      if (not ((c >= 'a' and c <= 'z') or 
               (c >= 'A' and c <= 'Z') or 
               (c >= '0' and c <= '9') or
               (c == '_' or c == '-'))) {
         return false;
      }
    };
    true
  };

  // Game database
  let games : Games = Buf.Buf<GameState>(0);

  // Two games are the same if their player names match.
  func same_game(game_A: GameState, game_B: GameState) : Bool {
    (game_A.black.1 == game_B.black.1 and game_A.white.1 == game_B.white.1)
  };

  func lookup_game_by_id(player_id: PlayerId): ?GameState {
    for (i in Iter.range(0, games.size()-1)) {
      let game = games.get(i);
      switch (game.black.0, game.white.0) {
        case (?black_id, ?white_id) {
          if (black_id == player_id or white_id == player_id) { return ?game; }
        };
        case (?black_id, null) { if (black_id == player_id) { return ?game; } };
        case (null, ?white_id) { if (white_id == player_id) { return ?game; } };
        case (null, null) {};
      }
    };
    null
  };

  // Return existing game that the given player is playing.
  // The condition of "playing" is equivalent to having the player_id in the game.
  // Otherwise, a game may have the player's name, but is only "expecting" the player.
  // It implies that a player can only play one game any any time, which could
  // be in any state: progressing, finished, or expecting another player.
  func lookup_game_by_name(player_name: PlayerName): ?GameState {
    for (i in Iter.range(0, games.size()-1)) {
      let game = games.get(i);
      let (black_id, black_name) = game.black;
      let (white_id, white_name) = game.white;
      if ((eq_nocase(white_name, player_name) and Option.isSome(white_id)) or 
          (eq_nocase(black_name, player_name) and Option.isSome(black_id))) {
        return ?game;
      }
    };
    null
  };

  // Delete a game from the existing games.
  func delete_game(game: GameState) {
    for (i in Iter.range(0, games.size()-1)) {
      if (same_game(game, games.get(i))) {
        for (j in Iter.range(i + 1, games.size()-1)) {
          let game = games.get(j);
          games.put(j-1, game); 
        };
        let _ = games.removeLast();
      }
    }
  };

  // Start a game with opponent. Rules are:
  // 1. A player can only start one game at any time. 
  // 2. 1st player to start a game will play black, 2nd player joining will play white.
  // 3. 2nd player to start will join an existing game if the opponent has already
  //    started a game waiting for this player.
  //
  // So the logic is to check whether the opponent has already started a game waiting
  // for this player. If so, join it. Otherwise, start a new game.
  //
  // It also means if white has left a game (to start another one), black can keep waiting.
  // But if black has left a game (to start another one), the game must be cancelled.
  public shared(msg) func start_game(opponent_name: Text): async Result.Result<GameView, StartError> {
    let player_id = msg.caller;
    switch (lookup_player_by_id(player_id)) {
      case null (#err(#PlayerNotFound));
      case (?player) {
        // allow empty opponent name
        if (opponent_name == "") {
          switch (lookup_game_by_name(player.name)) {
            case (?game) {
              // we have a game
              if (eq_nocase(game.white.1, player.name)) {
                // quit the existing one, and start another one.
                game.white := (null, "");
                return #ok(state_to_view(add_game(player_id, player.name, opponent_name)));
              } else {
                // reset the existing game
                game.white := (null, "");
                reset_game(game);
                return #ok(state_to_view(game))
              }
            };
            case null {
                return #ok(state_to_view(add_game(player_id, player.name, opponent_name)));
            };
          } 
        } else if (not valid_name(opponent_name)) {
          return #err(#InvalidOpponentName);
        };

        switch (lookup_game_by_name(player.name), lookup_game_by_name(opponent_name)) {
          // Both are in game
          case (?game_A, ?game_B) {
            if (same_game(game_A, game_B)) {
              if (Option.isSome(game_A.result)) {
                // Reset the game if it was already finished
                reset_game(game_A);
              };
              #ok(state_to_view(game_A))
            } else {
              // Not the same game, do not touch game_B.
              if (eq_nocase(player.name, game_A.black.1)) {
                // If player is black in game_A, we have changed the opponent, reset it
                game_A.white := (null, opponent_name);
                reset_game(game_A);
                #ok(state_to_view(game_A))
              } else {
                // If player is white in game_A, quit it, and start a new one
                game_A.white := (null, "");
                #ok(state_to_view(add_game(player_id, player.name, opponent_name)))
              }
            }
          };
          // opponent already in a game
          case (null, ?game) {
            // check if opponent is expecting no player or this player
            if (eq_nocase(game.black.1, player.name)) {
              game.black := (?player_id, player.name);
              #ok(state_to_view(game))
            } else if (eq_nocase(game.white.1, player.name) or game.white.1 == "") {
              game.white := (?player_id, player.name);
              #ok(state_to_view(game))
            } else {
              // start a new game
              #ok(state_to_view(add_game(player_id, player.name, opponent_name)))
            }
          };
          // this player already in a game
          case (?game, null) {
            if (eq_nocase(game.white.1, player.name)) {
              // remove this player from existing game, and start a new one
              game.white := (null, "");
              #ok(state_to_view(add_game(player_id, player.name, opponent_name)));
            } else {
              // this player is playing black, reset this game
              game.white := (null, opponent_name);
              reset_game(game);
              #ok(state_to_view(game))
            }
          };    
          // no existing game, start a new one
          case (null, null) {
            #ok(state_to_view(add_game(player_id, player.name, opponent_name)));
          }
        }
      }
    }
  };

  func reset_game(game: GameState) {
    let N = game.dimension;
    // clear the board
    for (i in Iter.range(0, N * N - 1)) {
         game.board[i] := empty; 
    };
    // initialize center 4 pieces
    let M = N / 2;
    game.board[(M - 1) * N + M - 1] := white;
    game.board[(M - 1) * N + M    ] := black;
    game.board[ M      * N + M    ] := white;
    game.board[ M      * N + M - 1] := black;
    game.moves.clear();
    game.moves.add(Nat8.fromNat((M - 1) * N + M - 1));
    game.moves.add(Nat8.fromNat((M - 1) * N + M    ));
    game.moves.add(Nat8.fromNat( M      * N + M    ));
    game.moves.add(Nat8.fromNat( M      * N + M - 1));
    game.next := #white;
    game.result := null;
  };

  // Create a new game, and add to the list of games.
  func add_game(black_id: PlayerId, black_name: Text, white_name: Text) : GameState {
    // default dimension is 6 for now
    let N = 6;
    let game = {
      dimension = N;
      board = Array.init<?Color>(N * N, empty);
      moves = Buf.Buf<Nat8>(N * N);
      var black : (?PlayerId, PlayerName) = (?black_id, black_name);
      var white : (?PlayerId, PlayerName) = (null, white_name);
      var next : Color = #white;
      var result : ?GameResult = null;
    };
    reset_game(game);
    games.add(game);
    game
  };

  // Return player level, which is just the number of digits in the player score (base10).
  func get_level(score: Nat) : Nat {
    let str = Nat.toText(score);
    str.size()
  };

  // Update player scores according to a GameResult. The rules are:
  // 1. The greater the level difference, the big you lose if your level is higher.
  // 2. The greater the level difference, the big you win if your level is lower.
  // 3. Extra bonus for finishing game early.
  func update_score(N: Nat, black_id: ?PlayerId, white_id: ?PlayerId, result: GameResult) {
    switch (Option.chain(black_id, lookup_player_by_id),
            Option.chain(white_id, lookup_player_by_id)) {
      case (?black_player, ?white_player) {
        let black_level = get_level(black_player.score);
        let white_level = get_level(white_player.score);
        let compute_score = func (points: Int, player_level: Nat, opponent_level: Nat): Int {
          if (points > 0) {
            points * opponent_level / player_level
          } else {
            points * player_level / opponent_level
          }
        };
        let bonus = 2 * N * N - result.black - result.white;
        let set_score = 
          func (player: PlayerState, points: Int, player_level: Nat, opponent_level: Nat) {
            let delta = compute_score(points, player_level, opponent_level);
            if (player.score + delta < 0) {
              player.score := 0;
            } else {
              player.score := Int.abs(player.score + delta);
            }
          };
        let points : Int = (result.black - result.white) * bonus / N / N;
        set_score(black_player, points, black_level, white_level);
        set_score(white_player, - points, white_level, black_level);
      };
      case _ {};
    }
  };
 
  func state_to_view(game: GameState): GameView {
    let (black_id, black_name) = game.black;
    let (white_id, white_name) = game.white;
    {
      black = (Option.map<PlayerId, ()>(black_id, func(_): () { () }), black_name);
      white = (Option.map<PlayerId, ()>(white_id, func(_): () { () }), white_name);
      board = render_board(game.dimension, game.board);
      dimension = game.dimension;
      next = game.next;
      result = game.result;
    }
  };

  // Render the board into a string
  func render_board(N: Nat, board: Board) : Text {
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

  // External interface to render the board
  public shared query(msg) func view() : async ?GameView {
      let player_id = msg.caller;
      Option.map(lookup_game_by_id(player_id), state_to_view)
  };

  // Given a color, return its opponent color
  func opponent(color: Color): Color {
      switch (color) {
        case (#black) #white;
        case (#white) #black;
      }
  };

  // Check if two ?Color value are the same.
  func match_color(a: ?Color, b: ?Color) : Bool {
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
      let next : Board = Array.init<?Color>(N * N, empty);
      for (i in Iter.range(0, N-1)) {
        for (j in Iter.range(0, N-1)) {
          if (match_color(board[i * N + j], empty) and valid_move(N, board, color, i, j)) {
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
      if (not match_color(c, empty)) {
        return false;
      }
    };
    true
  };


  // Return the white and black counts.
  func score(board: Board) : (Nat, Nat) {
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

  // External interface that places a piece of given color at a coordinate.
  // It returns "OK" when the move is valid.
  public shared(msg) func move(row_: Int, col_: Int) : async MoveResult {
    let player_id = msg.caller;
    switch (lookup_game_by_id(player_id)) {
      case null { #GameNotFound };
      case (?game) {
        switch (game.black, game.white) {
          case ((?black_id, _), (?white_id, _)) {
            let color = if (black_id == player_id) { #black } else { #white };
            let N = game.dimension;
            let board = game.board;
            let next_color = game.next;
            // The casting is necessary because dfx has yet to support Nat on commandline
            let row : Nat = Int.abs(row_); 
            let col : Nat = Int.abs(col_); 
      
            // Check input validity
            if (row >= N or col >= N) {
              return (#InvalidCoordinate);
            };
      
            if (not match_color(?next_color, ?color)) {
              return (#IllegalColor);
            };
      
            var possible = valid_moves(N, board, next_color);
      
            if (not match_color(possible[row * N + col], empty)) {
              game.moves.add(Nat8.fromNat(row * N + col));
              set_and_flip(N, board, color, row, col);
      
              // if opponent can't make a move, either pass or end game.
              var possible = valid_moves(N, board, opponent(color));
              if (is_empty(possible)) {
                possible := valid_moves(N, board, color);
                // If no possible move again, end game
                if (is_empty(possible)) {
                  let (wc, bc) = score(board);
                  let result : GameResult = { white = wc; black = bc; };
                  game.result := ?result;
                  update_score(N, game.black.0, game.white.0, result);
                  #GameOver(result)
                } else {
                  #Pass
                }
              } else {
                game.next := opponent(color);
                #OK
              }
            } else {
              #IllegalMove
            }
          };
          case _ { #GameNotStarted }
        }
      }
    }
  }
}

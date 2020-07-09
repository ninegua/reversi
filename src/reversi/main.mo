import Array "mo:base/Array";
import Buf "mo:base/Buf";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";
import Prim "mo:prim";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";

import Game "./game";

type PlayerId = Principal;
type PlayerName = Text;
type Score = Nat;

type MoveResult = {
  #GameNotFound;
  #GameNotStarted;
  #InvalidCoordinate;
  #InvalidColor;
  #IllegalMove;
  #IllegalColor;
  #GameOver: Game.ColorCount;
  #Pass;
  #OK;
};

type PlayerState = {
  name: PlayerName;
  var score: Score;
};

type PlayerView = {
  name: PlayerName;
  score: Score;
};

type Players = {
  id_map: HashMap.HashMap<PlayerId, PlayerState>;
  name_map: HashMap.HashMap<PlayerName, PlayerId>;
};

type ListResult = {
  top: [PlayerView];
  recent: [PlayerView];
  available: [PlayerView];
};

type RegistrationError = {
  #InvalidName;
  #NameAlreadyExists;
};

// History of valid moves. The use of Nat8 here implies the max dimension is 8.
type Moves = Buf.Buf<Nat8>;

type GameState = {
  dimension: Nat;
  board: Game.Board;
  moves: Moves;
  var black: (?PlayerId, PlayerName);
  var white: (?PlayerId, PlayerName);
  var next: Game.Color;
  var result: ?Game.ColorCount;
};

type GameView = {
  dimension: Nat;
  board: Text;
  moves: [Nat8];
  black: (?(), PlayerName);
  white: (?(), PlayerName);
  next: Game.Color;
  result: ?Game.ColorCount;
};

type Games = Buf.Buf<GameState>;

type StartError = {
  #InvalidOpponentName;
  #PlayerNotFound;
  #NoSelfGame;
  #OpponentInAnotherGame;
};

// Convert text to lower case
func to_lowercase(name: Text) : Text {
  var str = "";
  for (c in Text.toIter(name)) {
    let ch = if ('A' <= c and c <= 'Z') { Prim.word32ToChar(Prim.charToWord32(c) + 32) } else { c };
    str := str # Prim.charToText(ch);
  };
  str
};

// Text equality check ignoring cases.
func eq_nocase(s: Text, t: Text) : Bool {
  let m = s.size();
  let n = t.size();
  m == n and to_lowercase(s) == to_lowercase(t)
};

// Check if player name is valid, which is defined as:
// 1. Between 3 and 10 characters long
// 2. Alphanumerical. Special characters like  '_' and '-' are also allowed.
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

// Two games are the same if their player names match.
func same_game(game_A: GameState, game_B: GameState) : Bool {
  (game_A.black.1 == game_B.black.1 and game_A.white.1 == game_B.white.1)
};

// Reset a game to initial state.
func reset_game(game: GameState) {
    let N = game.dimension;
    let M = N / 2;
    let blacks = [ (M - 1, M), (M, M - 1) ];
    let whites = [ (M - 1, M - 1), (M, M) ];
    Game.init_board(N, game.board, blacks, whites);
    game.moves.clear();
    let add_move = func ((row: Nat, col: Nat)) {
      game.moves.add(Nat8.fromNat(row * N + col))
    };
    add_move(whites[0]);
    add_move(blacks[0]);
    add_move(whites[1]);
    add_move(blacks[1]);
    game.next := #white;
    game.result := null;
};

// Return player level, which is just the number of digits in the player score (base10).
func get_level(score: Nat) : Nat {
  let str = Nat.toText(score);
  str.size()
};

func player_state_to_view(player: PlayerState): PlayerView {
  { name = player.name; score = player.score; }
};

func game_state_to_view(game: GameState): GameView {
  let (black_id, black_name) = game.black;
  let (white_id, white_name) = game.white;
  {
    black = (Option.map<PlayerId, ()>(black_id, func(_): () { () }), black_name);
    white = (Option.map<PlayerId, ()>(white_id, func(_): () { () }), white_name);
    board = Game.render_board(game.dimension, game.board);
    moves = game.moves.toArray();
    dimension = game.dimension;
    next = game.next;
    result = game.result;
  }
};

func update_top_players(top_players: [var ?PlayerView], name_: PlayerName, score_: Score) {
  let N = top_players.size();
  // we first remove this player from the list if already exists
  label outer for (i in Iter.range(0, N - 1)) {
    switch (top_players[i]) {
      case null {
        break outer;
      };
      case (?player) {
        if (player.name == name_) {
          for (j in Iter.range(i, N -2)) {
            top_players[j] := top_players[j + 1];
          };
          top_players[N - 1] := null;
          break outer;
        }
      }
    }
  };
  // skip if new score is 0
  if (score_ == 0) { return; };
  // otherwise trying to insert.
  for (i in Iter.range(0, N - 1)) {
    switch (top_players[i]) {
      case null {
        top_players[i] := ?{ name = name_; score = score_ };
        return;
      };
      case (?player) {
        if (player.score < score_) {
           for (j in Iter.revRange(N - 1, i + 1)) {
             top_players[Int.abs(j)] := top_players[Int.abs(j - 1)];
           };
           top_players[i] := ?{ name = name_; score = score_ };
           return;
        }
      }
    }
  }
};

func update_fifo_player_list(fifo_players: [var PlayerName], name: PlayerName) {
  let N = fifo_players.size();
  for (i in Iter.range(0, N - 1)) {
    if (fifo_players[i] == "") {
      fifo_players[i] := name;
      return;
    } else if (fifo_players[i] == name) {
      if (i == N - 1 or fifo_players[i+1] == "") {
        return;
      };
      for (i in Iter.range(i, N - 2)) {
        fifo_players[i] := fifo_players[i+1];
      };
      fifo_players[N - 1] := "";
    }
  };
  for (i in Iter.range(0, N - 2)) {
    fifo_players[i] := fifo_players[i + 1];
  };
  fifo_players[N - 1] := name;
};

let update_recent_players = update_fifo_player_list;

func update_available_players(available_players: [var PlayerName], name: PlayerName, available: Bool) {
  let N = available_players.size();
  if (not available) {
    for (i in Iter.range(0, N - 1)) {
      if (available_players[i] == name) {
        for (i in Iter.range(i, N - 2)) {
          available_players[i] := available_players[i+1];
        };
        available_players[N - 1] := "";
        return;
      }
    }
  } else {
    update_fifo_player_list(available_players, name);
  }
};

func init_top_players(players: Iter.Iter<PlayerState>) : [var ?PlayerView] {
   let top_players = Array.init<?PlayerView>(10, null);
   Iter.iterate<PlayerState>(players, func(player, _) {
     update_top_players(top_players, player.name, player.score)
   });
   top_players
};

actor {

  // We use stable var to help keeping player data through upgrades.
  // This is necessary at the moment because HashMap cannot be made stable.
  // We also forego the requirement of persisting games, which is not as
  // crucial as keeping player accounts and scores.
  stable var accounts : [(PlayerId, PlayerState)] = [];

  // Before upgrade, we must dump all player data to stable accounts.
  system func preupgrade() {
    accounts := Iter.toArray(players.id_map.entries());
  };


  // Player database is initiated from the stable accounts.
  let players : Players = {
    id_map = HashMap.fromIter<PlayerId, PlayerState>(
      accounts.vals(), accounts.size(), func (x, y) { x == y }, Principal.hash
    );
    name_map = HashMap.fromIter<PlayerName, PlayerId>(
      Iter.map<(PlayerId, PlayerState), (PlayerName, PlayerId)>(
        accounts.vals(), func ((id, state)) { (to_lowercase(state.name), id) }
      ), accounts.size(), func (x, y) { x == y }, Text.hash
    );
  };

  let top_players : [var ?PlayerView] =
    init_top_players(
      Iter.map<(PlayerId, PlayerState), PlayerState>(
        accounts.vals(),
        func (x) { x.1 }
    ));
  let recent_players : [var PlayerName] = Array.init<PlayerName>(10, "");
  let available_players : [var PlayerName] = Array.init<PlayerName>(10, "");

  func lookup_player_by_id(id: PlayerId) : ?PlayerState {
    players.id_map.get(id)
  };

  func lookup_id_by_name(name: PlayerName) : ?PlayerId {
    players.name_map.get(to_lowercase(name))
  };

  func lookup_player_by_name(name: PlayerName) : ?PlayerState {
    switch (lookup_id_by_name(name)) {
      case null { null };
      case (?id) { lookup_player_by_id(id) };
    }
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
        update_recent_players(recent_players, player.name);
        #ok(player_state_to_view(player))
      };
      case (_, false) (#err(#InvalidName));
      case (null, true) {
        switch (lookup_id_by_name(name)) {
          case null {
              let player = insert_new_player(id, name);
              update_recent_players(recent_players, name);
              #ok(player_state_to_view(player))
          };
          case (?_) (#err(#NameAlreadyExists));
        }
      }
    }
  };

  // Game database
  let games : Games = Buf.Buf<GameState>(0);

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

  // proceed with a game and update player status
  func proceed(game: GameState) : GameView {
    if (Option.isSome(game.result)) {
      reset_game(game);
    };
    if (Option.isSome(game.black.0)) {
      update_available_players(available_players, game.black.1, true);
    };
    if (Option.isSome(game.white.0)) {
      update_available_players(available_players, game.white.1, true);
    };
    game_state_to_view(game)
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
  public shared(msg) func start(opponent_name: Text): async Result.Result<GameView, StartError> {
    let player_id = msg.caller;
    switch (lookup_player_by_id(player_id)) {
      case null (#err(#PlayerNotFound));
      case (?player) {
        if (player.name == opponent_name) {
          return #err(#NoSelfGame);
        } else if (opponent_name == "") {
          // allow empty opponent name
          switch (lookup_game_by_name(player.name)) {
            case (?game) {
              // We have a game
              if (eq_nocase(game.black.1, player.name) and Option.isNull(game.white.0)) {
                // Opponent has not arrived or already left, cancel it
                game.white := (null, "");
                reset_game(game);
                return #ok(proceed(game));
              } else if (Option.isNull(game.result)) {
                // Still live? Continue
                return #ok(proceed(game));
              } else {
                // Already ended? Delete it.
                delete_game(game);
              }
            };
            case null {}
          };
          return #ok(proceed(add_game(player_id, player.name, opponent_name)));
        } else if (not valid_name(opponent_name)) {
          return #err(#InvalidOpponentName);
        };

        switch (lookup_game_by_name(player.name), lookup_game_by_name(opponent_name)) {
          // opponent already in a game
          case (game, ?game_B) {
            switch (game) {
              case (?game_A) {
                if (not (same_game(game_A, game_B))) {
                  // must quit from existing game if it is not the same as game_B
                  if (eq_nocase(game_A.black.1, player.name)) {
                    delete_game(game_A);
                  } else {
                    game_A.white := (null, "");
                  }
                }
              };
              case null {}
            };
            // check if opponent is expecting no player or this player
            if (eq_nocase(game_B.black.1, player.name)) {
              game_B.black := (?player_id, player.name);
              #ok(proceed(game_B))
            } else if (eq_nocase(game_B.white.1, player.name) or game_B.white.1 == "") {
              game_B.white := (?player_id, player.name);
              #ok(proceed(game_B))
            } else {
              #err(#OpponentInAnotherGame);
            }
          };
          // this player already in a game
          case (?game, null) {
            if (eq_nocase(game.white.1, player.name)) {
              // remove this player from existing game, and start a new one
              game.white := (null, "");
              #ok(proceed(add_game(player_id, player.name, opponent_name)));
            } else {
              // this player is playing black, reset this game
              game.white := (null, opponent_name);
              reset_game(game);
              #ok(proceed(game))
            }
          };
          // no existing game, start a new one
          case (null, null) {
            #ok(proceed(add_game(player_id, player.name, opponent_name)));
          }
        }
      }
    }
  };

  // Create a new game, and add to the list of games.
  func add_game(black_id: PlayerId, black_name: Text, white_name: Text) : GameState {
    // default dimension is 6 for now
    let N = 6;
    let game = {
      dimension = N;
      board = Array.init<?Game.Color>(N * N, Game.empty_piece);
      moves = Buf.Buf<Nat8>(N * N);
      var black : (?PlayerId, PlayerName) = (?black_id, black_name);
      var white : (?PlayerId, PlayerName) = (null, white_name);
      var next : Game.Color = #white;
      var result : ?Game.ColorCount = null;
    };
    reset_game(game);
    games.add(game);
    game
  };

  // Update player scores according to a GameResult. The rules are:
  // 1. The greater the level difference, the big you lose if your level is higher.
  // 2. The greater the level difference, the big you win if your level is lower.
  // 3. Extra bonus for finishing game early.
  func update_score(N: Nat, black_id: ?PlayerId, white_id: ?PlayerId, result: Game.ColorCount) {
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
            };
            update_top_players(top_players, player.name, player.score);
          };
        let points : Int = (result.black - result.white) * bonus / N / N;
        set_score(black_player, points, black_level, white_level);
        set_score(white_player, - points, white_level, black_level);
      };
      case _ {};
    }
  };

  // List top/recent/available players.
  public query func list(): async ListResult {
    let names_to_view = func(arr: [var PlayerName], count: Nat) : [PlayerView] {
      Array.map<?PlayerView, PlayerView>(
        Array.filter<?PlayerView>(
          Option.isSome,
          Array.tabulate<?PlayerView>(count, func(i) {
            Option.map<PlayerState, PlayerView>(
              lookup_player_by_name(arr[i]),
              player_state_to_view)
          })),
        func(x) { Option.unwrap<PlayerView>(x) } )
    };
    let count_until = func<A>(arr: [var A], f: A -> Bool) : Nat {
       var n = 0;
       for (i in Iter.range(0, arr.size() - 1)) {
         if (f(arr[i])) { return n; };
         n := n + 1;
       };
       return n;
    };
    let n_top = count_until<?PlayerView>(top_players, Option.isNull);
    let n_recent = count_until<PlayerName>(recent_players, func(x) { x=="" });
    let n_available = count_until<PlayerName>(available_players, func(x) { x=="" });
    {
      top = Array.tabulate<PlayerView>(n_top, func(i) { Option.unwrap(top_players[i]) });
      recent = names_to_view(recent_players, n_recent);
      available = names_to_view(available_players, n_available);
    }
  };

  // External interface to view the state of an on-going game.
  public shared query(msg) func view() : async ?GameView {
      let player_id = msg.caller;
      Option.map(lookup_game_by_id(player_id), game_state_to_view)
  };

  // External interface that places a piece of given color at a coordinate.
  // It returns "OK" when the move is valid.
  public shared(msg) func move(row_: Int, col_: Int) : async MoveResult {
    // The casting is necessary because dfx has yet to support Nat on commandline
    let row : Nat = Int.abs(row_);
    let col : Nat = Int.abs(col_);
    let player_id = msg.caller;
    switch (lookup_game_by_id(player_id)) {
      case null { #GameNotFound };
      case (?game) {
        switch (game.black, game.white) {
          case ((?black_id, _), (?white_id, _)) {
            let color = if (black_id == player_id) { #black } else { #white };
            if (not Game.match_color(?game.next, ?color)) {
              return (#IllegalColor);
            };

            switch (Game.place(game.dimension, game.board, color, row, col)) {
              case (#InvalidCoordinate) {
                #InvalidCoordinate
              };
              case (#IllegalMove) {
                #IllegalMove
              };
              case (#OK) {
                game.moves.add(Nat8.fromNat(row * game.dimension + col));
                game.next := Game.opponent(color);
                #OK
              };
              case (#Pass) {
                game.moves.add(Nat8.fromNat(row * game.dimension + col));
                #Pass
              };
              case (#GameOver(result)) {
                game.result := ?result;
                update_score(game.dimension, game.black.0, game.white.0, result);
                #GameOver(result)
              };
            }
          };
          case _ { #GameNotStarted }
        }
      }
    }
  }
}

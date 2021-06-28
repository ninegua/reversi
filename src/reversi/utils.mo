import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";
import Prim "mo:prim";
import Types "./types";
import Text "mo:base/Text";
import Time "mo:base/Time";

import Game "./game";

module {

// Game with no movement will expire.
public let game_expired_nanosecs = 600000000000; // 10 minutes
public let game_expiring_nanosecs = 540000000000; // 9 minutes

public type Iter<T> = Iter.Iter<T>;
public type GameState = Types.GameState;
public type GameView = Types.GameView;
public type PlayerId = Types.PlayerId;
public type PlayerName = Types.PlayerName;
public type PlayerState = Types.PlayerStateV2;
public type PlayerView = Types.PlayerView;
public type Score = Types.Score;

// Convert text to lower case
public func to_lowercase(name: Text) : Text {
  var str = "";
  for (c in Text.toIter(name)) {
    let ch = if ('A' <= c and c <= 'Z') { Prim.charToLower(c) } else { c };
    str := str # Prim.charToText(ch);
  };
  str
};

// Text equality check ignoring cases.
public func eq_nocase(s: Text, t: Text) : Bool {
  let m = s.size();
  let n = t.size();
  m == n and to_lowercase(s) == to_lowercase(t)
};

// Check if player name is valid, which is defined as:
// 1. Between 3 and 10 characters long
// 2. Alphanumerical. Special characters like  '_' and '-' are also allowed.
public func valid_name(name: Text): Bool {
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
public func same_game(game_A: GameState, game_B: GameState) : Bool {
  (game_A.black.1 == game_B.black.1 and game_A.white.1 == game_B.white.1)
};

// Reset a game to initial state.
public func reset_game(game: GameState) {
    let N = game.dimension;
    let M = N / 2;
    let blacks : [(Nat,Nat)] = [ (M - 1, M), (M, M - 1) ];
    let whites : [(Nat,Nat)] = [ (M - 1, M - 1), (M, M) ];
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
public func get_level(score: Nat) : Nat {
  let str = Nat.toText(score);
  str.size()
};

public func player_state_to_view(player: PlayerState): PlayerView {
  { name = player.name; score = player.score; }
};

public func update_top_players(top_players: [var ?PlayerView], name_: PlayerName, score_: Score) {
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

public func update_fifo_player_list(fifo_players: [var PlayerName], name: PlayerName) {
  let N = fifo_players.size();
  func remove(names: [var PlayerName], name: PlayerName) {
    for (i in Iter.range(0, N - 1)) {
      if (names[i] == name) {
        for (j in Iter.range(i, N - 2)) {
          names[j] := names[j + 1];
        };
        names[N-1] := "";
      }
    }
  };
  func add(names: [var PlayerName], name: PlayerName) {
    for (i in Iter.range(0, N - 1)) {
      if (fifo_players[i] == "") {
        fifo_players[i] := name;
        return;
      }
    };
    remove(names, names[0]);
    names[N-1] := name;
  };
  remove(fifo_players, name);
  add(fifo_players, name);
};

public let update_recent_players = update_fifo_player_list;

public func update_available_players(available_players: [var PlayerName], name: PlayerName, available: Bool) {
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

public func init_top_players(players: Iter<PlayerState>) : [var ?PlayerView] {
   let top_players = Array.init<?PlayerView>(10, null);
   Iter.iterate<PlayerState>(players, func(player, _) {
     update_top_players(top_players, player.name, player.score)
   });
   top_players
};

}

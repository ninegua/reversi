import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
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
import Types "./types";
import Utils "./utils";

actor {

  type Result<T,E> = Result.Result<T,E>;
  type Players = Types.Players;
  type PlayerId = Types.PlayerId;
  type PlayerName = Types.PlayerName;
  type PlayerState = Types.PlayerState;
  type PlayerView = Types.PlayerView;
  type Games = Types.Games;
  type GameState = Types.GameState;
  type GameView = Types.GameView;

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
        accounts.vals(), func ((id, state)) { (Utils.to_lowercase(state.name), id) }
      ), accounts.size(), func (x, y) { x == y }, Text.hash
    );
  };

  let top_players : [var ?PlayerView] =
    Utils.init_top_players(
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
    players.name_map.get(Utils.to_lowercase(name))
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
    players.name_map.put(Utils.to_lowercase(name_), id);
    player
  };

  // Player login/registration. If the caller is not already found in the player database,
  // a new account is created with the given name. Otherwise the given name is ignored.
  // Return player info if the player is found or successfully registered, or an registration
  // error.
  public shared(msg) func register(name: Text): async Result<PlayerView, Types.RegistrationError> {
    let player_id = msg.caller;
    switch (lookup_player_by_id(player_id), Utils.valid_name(name)) {
      case (?player, _) {
        Utils.update_recent_players(recent_players, player.name);
        #ok(Utils.player_state_to_view(player))
      };
      case (_, false) (#err(#InvalidName));
      case (null, true) {
        switch (lookup_id_by_name(name)) {
          case null {
              let player = insert_new_player(player_id, name);
              Utils.update_recent_players(recent_players, name);
              #ok(Utils.player_state_to_view(player))
          };
          case (?_) (#err(#NameAlreadyExists));
        }
      }
    }
  };

  // Game database
  let games : Games = Buffer.Buffer<GameState>(0);

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
      if ((Utils.eq_nocase(white_name, player_name) and Option.isSome(white_id)) or
          (Utils.eq_nocase(black_name, player_name) and Option.isSome(black_id))) {
        return ?game;
      }
    };
    null
  };

  // Delete a game from the existing games.
  func delete_game(game: GameState) {
    for (i in Iter.range(0, games.size()-1)) {
      if (Utils.same_game(game, games.get(i))) {
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
      Utils.reset_game(game);
    };
    if (Option.isSome(game.black.0)) {
      Utils.update_available_players(available_players, game.black.1, true);
    };
    if (Option.isSome(game.white.0)) {
      Utils.update_available_players(available_players, game.white.1, true);
    };
    Utils.game_state_to_view(game)
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
  public shared (msg) func start(opponent_name: Text): async Result<GameView, Types.StartError> {
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
              if (Utils.eq_nocase(game.black.1, player.name) and Option.isNull(game.white.0)) {
                // Opponent has not arrived or already left, cancel it
                game.white := (null, "");
                Utils.reset_game(game);
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
        } else if (not Utils.valid_name(opponent_name)) {
          return #err(#InvalidOpponentName);
        };

        switch (lookup_game_by_name(player.name), lookup_game_by_name(opponent_name)) {
          // opponent already in a game
          case (game, ?game_B) {
            switch (game) {
              case (?game_A) {
                if (not (Utils.same_game(game_A, game_B))) {
                  // must quit from existing game if it is not the same as game_B
                  if (Utils.eq_nocase(game_A.black.1, player.name)) {
                    delete_game(game_A);
                  } else {
                    game_A.white := (null, "");
                  }
                }
              };
              case null {}
            };
            // check if opponent is expecting no player or this player
            if (Utils.eq_nocase(game_B.black.1, player.name)) {
              game_B.black := (?player_id, player.name);
              #ok(proceed(game_B))
            } else if (Utils.eq_nocase(game_B.white.1, player.name) or game_B.white.1 == "") {
              game_B.white := (?player_id, player.name);
              #ok(proceed(game_B))
            } else {
              #err(#OpponentInAnotherGame);
            }
          };
          // this player already in a game
          case (?game, null) {
            if (Utils.eq_nocase(game.white.1, player.name)) {
              // remove this player from existing game, and start a new one
              game.white := (null, "");
              #ok(proceed(add_game(player_id, player.name, opponent_name)));
            } else {
              // this player is playing black, reset this game
              game.white := (null, opponent_name);
              Utils.reset_game(game);
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
      moves = Buffer.Buffer<Nat8>(N * N);
      var black : (?PlayerId, PlayerName) = (?black_id, black_name);
      var white : (?PlayerId, PlayerName) = (null, white_name);
      var next : Game.Color = #white;
      var result : ?Game.ColorCount = null;
    };
    Utils.reset_game(game);
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
        let black_level = Utils.get_level(black_player.score);
        let white_level = Utils.get_level(white_player.score);
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
            Utils.update_top_players(top_players, player.name, player.score);
          };
        let points : Int = (result.black - result.white) * bonus / N / N;
        set_score(black_player, points, black_level, white_level);
        set_score(white_player, - points, white_level, black_level);
      };
      case _ {};
    }
  };

  // List top/recent/available players.
  public query func list(): async Types.ListResult {
    let names_to_view = func(arr: [var PlayerName], count: Nat) : [PlayerView] {
      Array.map<?PlayerView, PlayerView>(
        Array.filter<?PlayerView>(
          Array.tabulate<?PlayerView>(count, func(i) {
            Option.map<PlayerState, PlayerView>(
              lookup_player_by_name(arr[i]),
              Utils.player_state_to_view)
          }),
          Option.isSome),
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
  public shared query (msg) func view() : async ?GameView {
      let player_id = msg.caller;
      Option.map(lookup_game_by_id(player_id), Utils.game_state_to_view)
  };

  // External interface that places a piece of given color at a coordinate.
  // It returns "OK" when the move is valid.
  public shared(msg) func move(row_: Int, col_: Int) : async Types.MoveResult {
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
                game.moves.add(Nat8.fromNat(row * game.dimension + col));
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

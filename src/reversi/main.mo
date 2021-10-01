import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
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
import Time "mo:base/Time";

import Game "./game";
import Types "./types";
import Utils "./utils";

actor {

  type Result<T,E> = Result.Result<T,E>;
  type Players = Types.Players;
  type PlayerId = Types.PlayerId;
  type PlayerName = Types.PlayerName;
  type PlayerStateV1 = Types.PlayerStateV1;
  type PlayerState = Types.PlayerStateV2;
  type PlayerView = Types.PlayerView;
  type Games = Types.Games;
  type GameState = Types.GameState;
  type GamePlayer = Types.GamePlayer;
  type GameView = Types.GameView;
  type IdMap = Types.IdMap;
  type NameMap = Types.NameMap;

  // We use stable var to help keeping player data through upgrades.
  // This is necessary at the moment because HashMap cannot be made stable.
  // We also forego the requirement of persisting games, which is not as
  // crucial as keeping player accounts and scores.
  stable var accounts : [(PlayerId, PlayerStateV1)] = [];
  stable var accounts_v2 : [PlayerState] = [];

  func allAccounts() : [PlayerState] {
    Array.append(
      accounts_v2,
      Array.map(accounts,
        func ((id, state): (PlayerId, PlayerStateV1)): PlayerState {
          { name = state.name; ids = [id]; var score = state.score }
        }
      )
    )
  };

  func allAccountsSize() : Nat {
    accounts.size() + accounts_v2.size()
  };

  // Before upgrade, we must dump all player data to stable accounts.
  system func preupgrade() {
    accounts := [];
    accounts_v2 := Iter.toArray(Iter.map(
                  players.name_map.entries(), 
                  func (x: (PlayerName, PlayerState)) : PlayerState { x.1 }
                ));
  };


  // Player database is initiated from the stable accounts.
  let players : Players = {
    id_map : IdMap = Array.foldLeft(
      allAccounts(),
      HashMap.HashMap<PlayerId, PlayerName>(
        allAccountsSize(), func (x, y) { x == y }, Principal.hash
      ),
      func(m: IdMap, state: PlayerState) : IdMap {
        for (id in state.ids.vals()) {
          m.put(id, state.name)
        };
        m
      }
    );
    name_map : NameMap = HashMap.fromIter<PlayerName, PlayerState>(
      Iter.map<PlayerState, (PlayerName, PlayerState)>(
        allAccounts().vals(),
        func(state: PlayerState): (PlayerName, PlayerState) {
          (state.name, state)
        }),
      allAccountsSize(),
      func (x, y) { x == y }, Text.hash
    );
  };

  let top_players : [var ?PlayerView] = Utils.init_top_players(allAccounts().vals());
  let recent_players : [var PlayerName] = Array.init<PlayerName>(10, "");
  let available_players : [var PlayerName] = Array.init<PlayerName>(10, "");

  func lookup_player_by_id(id: PlayerId) : ?PlayerState {
    Option.chain(players.id_map.get(id), players.name_map.get)
  };

  func lookup_player_by_name(name: PlayerName) : ?PlayerState {
    players.name_map.get(name)
  };

  func game_state_to_view(game: GameState, ): GameView {
    func to_gameplayer(player: (?PlayerId, PlayerName)) : GamePlayer {
       switch (player.0) {
         case null (#PlayerName(player.1));
         case (?player_id) {
           switch (lookup_player_by_id(player_id)) {
             case null (#PlayerName(player.1));
             case (?player) (#Player(player_id, Utils.player_state_to_view(player)));
           }
         }
       }
    };

    {
      black = to_gameplayer(game.black);
      white = to_gameplayer(game.white);
      board = Game.render_board(game.dimension, game.board);
      moves = game.moves.toArray();
      dimension = game.dimension;
      next = game.next;
      result = game.result;
      expiring = game.last_updated + Utils.game_expiring_nanosecs < Time.now();
    }
  };

  func insert_new_player(id: PlayerId, name_: PlayerName) : PlayerState {
    let player_name = Utils.to_lowercase(name_);
    let player = { name = player_name; ids = [id]; var score = 0 };
    players.name_map.put(player_name, player);
    players.id_map.put(id, player_name);
    player
  };

  // Player login/registration. If the caller is not already found in the player database,
  // a new account is created with the given name. Otherwise the given name is ignored.
  // Return player info if the player is found or successfully registered, or an registration
  // error.
  public shared(msg) func register(name: Text): async Result<PlayerView, Types.RegistrationError> {
    let player_id = msg.caller;
    Debug.print("caller: " # Principal.toText(player_id));
    switch (lookup_player_by_id(player_id), Utils.valid_name(name)) {
      case (?player, _) {
        Utils.update_recent_players(recent_players, player.name);
        #ok(Utils.player_state_to_view(player))
      };
      case (_, false) (#err(#InvalidName));
      case (null, true) {
        switch (lookup_player_by_name(name)) {
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
      if (game.black.0 == ?player_id) { return ?game };
      if (game.white.0 == ?player_id) { return ?game };
    };
    null
  };

  // Return all games that the given player might be playing.
  func lookup_games_by_name(player_name: PlayerName): [GameState] {
    Array.filter(games.toArray(), func (game: GameState) : Bool {
      let (black_id, black_name) = game.black;
      let (white_id, white_name) = game.white;
      Utils.eq_nocase(white_name, player_name) or Utils.eq_nocase(black_name, player_name)
    })
  };

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
    var n = games.size();
    var i = 0;
    while (i < n) {
      if (Utils.same_game(game, games.get(i))) {
        for (j in Iter.range(i + 1, games.size()-1)) {
          let game = games.get(j);
          games.put(j-1, game);
        };
        let _ = games.removeLast();
        n := n - 1
      } else {
        i := i + 1
      }
    }
  };

  // Purge expired games has no movement for 10 minutes.
  func purge_expired_games() {
    var n = games.size();
    var i = 0;
    let now = Time.now();
    while (i < n) {
      let game = games.get(i);
      if (game.last_updated + Utils.game_expired_nanosecs < now) {
        switch (games.removeLast()) {
          case null ();
          case (?game) games.put(i, game);
        };
        n := n - 1
      } else {
        i := i + 1
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
    game_state_to_view(game)
  };

  // Invite a player to a game
  // public shared (msg) func invite(opponent_name: Text): async Result<GameView, Types.StartError> {
  // };

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
    purge_expired_games();
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
                game.last_updated := Time.now();
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
                    game_A.last_updated := Time.now();
                  }
                }
              };
              case null {}
            };
            // check if opponent is expecting no player or this player
            if (Utils.eq_nocase(game_B.black.1, player.name)) {
              game_B.black := (?player_id, player.name);
              game_B.last_updated := Time.now();
              #ok(proceed(game_B))
            } else if (Utils.eq_nocase(game_B.white.1, player.name) or game_B.white.1 == "") {
              game_B.white := (?player_id, player.name);
              game_B.last_updated := Time.now();
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
              game.last_updated := Time.now();
              #ok(proceed(add_game(player_id, player.name, opponent_name)));
            } else {
              // this player is playing black, reset this game
              game.white := (null, opponent_name);
              game.last_updated := Time.now();
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
      var last_updated = Time.now();
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
        let bonus : Nat = 2 * N * N - result.black - result.white;
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

  // List (my) pending games, and top/recent/available players.
  public shared query (msg) func list(): async Types.ListResult {
    let player_id = msg.caller;
    let player = lookup_player_by_id(player_id);
    let player_name = Option.map(player, func (state: PlayerState): PlayerName { state.name });
    let names_to_view = func(arr: [var PlayerName], count: Nat) : [PlayerView] {
      Array.mapFilter<?PlayerView, PlayerView>(
          Array.tabulate<?PlayerView>(count, func(i) {
            Option.map<PlayerState, PlayerView>(
              lookup_player_by_name(arr[i]),
              Utils.player_state_to_view)
          }),
          func (x) { x })
    };
    let count_until = func<A>(arr: [var A], f: A -> Bool) : Nat {
       var n = 0;
       for (i in Iter.range(0, arr.size() - 1)) {
         if (f(arr[i])) { return n };
         n := n + 1;
       };
       return n;
    };
    let n_recent = count_until<PlayerName>(recent_players, func(x) { x=="" });
    let n_available = count_until<PlayerName>(available_players, func(x) { x=="" });
    {
      top = Array.mapFilter<?PlayerView, PlayerView>(Array.freeze(top_players), func(x) { x });
      recent = names_to_view(recent_players, n_recent);
      available = names_to_view(available_players, n_available);
      player = Option.map(player, Utils.player_state_to_view);
      games = Array.map(
        Option.getMapped(player_name, lookup_games_by_name, []),
        game_state_to_view);
    }
  };

  // External interface to view the state of an on-going game.
  public shared query (msg) func view() : async ?GameView {
      let player_id = msg.caller;
      Option.map(lookup_game_by_id(player_id), game_state_to_view)
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
                game.last_updated := Time.now();
                #OK
              };
              case (#Pass) {
                game.moves.add(Nat8.fromNat(row * game.dimension + col));
                #Pass
              };
              case (#GameOver(result)) {
                game.moves.add(Nat8.fromNat(row * game.dimension + col));
                game.result := ?result;
                game.last_updated := Time.now();
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

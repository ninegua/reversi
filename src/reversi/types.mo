import Buffer "mo:base/Buffer";
import HashMap "mo:base/HashMap";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Game "./game";
import Text "mo:base/Text";
import Time "mo:base/Time";

module {

public type Result<T,E> = Result.Result<T,E>;
public type PlayerId = Principal;
public type PlayerName = Text;
public type Score = Nat;

// func t(x: Result<(), ()>) : ()  { Result.unwrapOk(x) };

public type MoveResult = {
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

public type PlayerStateV1 = {
  name: PlayerName;
  var score: Score;
};

public type PlayerStateV2 = {
  name: PlayerName;
  ids: [PlayerId];
  var score: Score;
};

public type PlayerView = {
  name: PlayerName;
  score: Score;
};

public type IdMap = HashMap.HashMap<PlayerId, PlayerName>;
public type NameMap = HashMap.HashMap<PlayerName, PlayerStateV2>;

public type Players = {
  id_map: IdMap;
  name_map: NameMap;
};

public type ListResult = {
  top: [PlayerView];
  recent: [PlayerView];
  available: [PlayerView];
  player: ?PlayerView;
  games: [GameView];
};

public type RegistrationError = {
  #InvalidName;
  #NameAlreadyExists;
};

// History of valid moves. The use of Nat8 here implies the max dimension is 8.
public type Moves = Buffer.Buffer<Nat8>;

public type GameState = {
  dimension: Nat;
  board: Game.Board;
  moves: Moves;
  var black: (?PlayerId, PlayerName);
  var white: (?PlayerId, PlayerName);
  var next: Game.Color;
  var result: ?Game.ColorCount;
  var last_updated: Time.Time;
};

public type GamePlayer = {
  #Player: (PlayerId, PlayerView);
  #PlayerName: PlayerName;
};

public type GameView = {
  dimension: Nat;
  board: Text;
  moves: [Nat8];
  black: GamePlayer;
  white: GamePlayer;
  next: Game.Color;
  result: ?Game.ColorCount;
  expiring: Bool;
};

public type Games = Buffer.Buffer<GameState>;

public type StartError = {
  #InvalidOpponentName;
  #PlayerNotFound;
  #NoSelfGame;
  #OpponentInAnotherGame;
};

}


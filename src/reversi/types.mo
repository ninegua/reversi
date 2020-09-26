import Buffer "mo:base/Buffer";
import HashMap "mo:base/HashMap";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Game "./game";
import Text "mo:base/Text";

type Result<T,E> = Result.Result<T,E>;
type PlayerId = Principal;
type PlayerName = Text;
type Score = Nat;

// func t(x: Result<(), ()>) : ()  { Result.unwrapOk(x) };

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
type Moves = Buffer.Buffer<Nat8>;

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

type Games = Buffer.Buffer<GameState>;

type StartError = {
  #InvalidOpponentName;
  #PlayerNotFound;
  #NoSelfGame;
  #OpponentInAnotherGame;
};

import type { Principal } from '@dfinity/principal';
import type { ActorMethod } from '@dfinity/agent';

export type Color = { 'black' : null } |
  { 'white' : null };
export interface ColorCount { 'black' : bigint, 'white' : bigint }
export type GamePlayer = { 'Player' : [PlayerId, PlayerView] } |
  { 'PlayerName' : PlayerName };
export interface GameView {
  'result' : [] | [ColorCount],
  'moves' : Uint8Array | number[],
  'next' : Color,
  'dimension' : bigint,
  'expiring' : boolean,
  'black' : GamePlayer,
  'board' : string,
  'white' : GamePlayer,
}
export interface GameView__1 {
  'result' : [] | [ColorCount],
  'moves' : Uint8Array | number[],
  'next' : Color,
  'dimension' : bigint,
  'expiring' : boolean,
  'black' : GamePlayer,
  'board' : string,
  'white' : GamePlayer,
}
export interface ListResult {
  'top' : Array<PlayerView>,
  'player' : [] | [PlayerView],
  'available' : Array<PlayerView>,
  'games' : Array<GameView__1>,
  'recent' : Array<PlayerView>,
}
export type MoveResult = { 'OK' : null } |
  { 'Pass' : null } |
  { 'GameNotStarted' : null } |
  { 'IllegalColor' : null } |
  { 'IllegalMove' : null } |
  { 'GameOver' : ColorCount } |
  { 'GameNotFound' : null } |
  { 'InvalidColor' : null } |
  { 'InvalidCoordinate' : null };
export type PlayerId = Principal;
export type PlayerName = string;
export interface PlayerView { 'name' : PlayerName, 'score' : Score }
export interface PlayerView__1 { 'name' : PlayerName, 'score' : Score }
export type RegistrationError = { 'NameAlreadyExists' : null } |
  { 'InvalidName' : null };
export type Result = { 'ok' : GameView } |
  { 'err' : StartError };
export type Result_1 = { 'ok' : PlayerView__1 } |
  { 'err' : RegistrationError };
export type Score = bigint;
export type StartError = { 'NoSelfGame' : null } |
  { 'PlayerNotFound' : null } |
  { 'InvalidOpponentName' : null } |
  { 'OpponentInAnotherGame' : null };
export interface _SERVICE {
  'list' : ActorMethod<[], ListResult>,
  'move' : ActorMethod<[bigint, bigint], MoveResult>,
  'register' : ActorMethod<[string], Result_1>,
  'start' : ActorMethod<[string], Result>,
  'view' : ActorMethod<[], [] | [GameView]>,
  'view_game' : ActorMethod<[string, string], [] | [GameView]>,
  'view_possible' : ActorMethod<[Color, Principal, Principal], string>,
}

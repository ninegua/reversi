export const idlFactory = ({ IDL }) => {
  const PlayerName = IDL.Text;
  const Score = IDL.Nat;
  const PlayerView = IDL.Record({ 'name' : PlayerName, 'score' : Score });
  const ColorCount = IDL.Record({ 'black' : IDL.Nat, 'white' : IDL.Nat });
  const Color = IDL.Variant({ 'black' : IDL.Null, 'white' : IDL.Null });
  const PlayerId = IDL.Principal;
  const GamePlayer = IDL.Variant({
    'Player' : IDL.Tuple(PlayerId, PlayerView),
    'PlayerName' : PlayerName,
  });
  const GameView__1 = IDL.Record({
    'result' : IDL.Opt(ColorCount),
    'moves' : IDL.Vec(IDL.Nat8),
    'next' : Color,
    'dimension' : IDL.Nat,
    'expiring' : IDL.Bool,
    'black' : GamePlayer,
    'board' : IDL.Text,
    'white' : GamePlayer,
  });
  const ListResult = IDL.Record({
    'top' : IDL.Vec(PlayerView),
    'player' : IDL.Opt(PlayerView),
    'available' : IDL.Vec(PlayerView),
    'games' : IDL.Vec(GameView__1),
    'recent' : IDL.Vec(PlayerView),
  });
  const MoveResult = IDL.Variant({
    'OK' : IDL.Null,
    'Pass' : IDL.Null,
    'GameNotStarted' : IDL.Null,
    'IllegalColor' : IDL.Null,
    'IllegalMove' : IDL.Null,
    'GameOver' : ColorCount,
    'GameNotFound' : IDL.Null,
    'InvalidColor' : IDL.Null,
    'InvalidCoordinate' : IDL.Null,
  });
  const PlayerView__1 = IDL.Record({ 'name' : PlayerName, 'score' : Score });
  const RegistrationError = IDL.Variant({
    'NameAlreadyExists' : IDL.Null,
    'InvalidName' : IDL.Null,
  });
  const Result_1 = IDL.Variant({
    'ok' : PlayerView__1,
    'err' : RegistrationError,
  });
  const GameView = IDL.Record({
    'result' : IDL.Opt(ColorCount),
    'moves' : IDL.Vec(IDL.Nat8),
    'next' : Color,
    'dimension' : IDL.Nat,
    'expiring' : IDL.Bool,
    'black' : GamePlayer,
    'board' : IDL.Text,
    'white' : GamePlayer,
  });
  const StartError = IDL.Variant({
    'NoSelfGame' : IDL.Null,
    'PlayerNotFound' : IDL.Null,
    'InvalidOpponentName' : IDL.Null,
    'OpponentInAnotherGame' : IDL.Null,
  });
  const Result = IDL.Variant({ 'ok' : GameView, 'err' : StartError });
  return IDL.Service({
    'list' : IDL.Func([], [ListResult], ['query']),
    'move' : IDL.Func([IDL.Int, IDL.Int], [MoveResult], []),
    'register' : IDL.Func([IDL.Text], [Result_1], []),
    'start' : IDL.Func([IDL.Text], [Result], []),
    'view' : IDL.Func([], [IDL.Opt(GameView)], ['query']),
    'view_game' : IDL.Func(
        [IDL.Text, IDL.Text],
        [IDL.Opt(GameView)],
        ['query'],
      ),
    'view_possible' : IDL.Func(
        [Color, IDL.Principal, IDL.Principal],
        [IDL.Text],
        ['query'],
      ),
  });
};
export const init = ({ IDL }) => { return []; };

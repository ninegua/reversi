//////////////////////////////////////////////////////////////////////////////
// Game error handling
//////////////////////////////////////////////////////////////////////////////

var error = { code: null, arg: null };

export function clear_error() {
  error = { code: null, arg: null };
}

export function set_error(code, arg) {
  error.code = code;
  error.arg = arg;
}

export function get_error_message() {
  if (!error.code) {
    return "";
  }
  let msgs = {
    NoSelfGame: "Please input an opponent other than yourself.",
    InvalidName:
      "Name must be alphanumerical with no space, and between 3 and 10 characters long.",
    InvalidOpponentName:
      "Opponent name must be alphanumerical with no space, and between 3 and 10 characters long.",
    NameAlreadyExists:
      "Name '" + (error.arg ? error.arg : "") + "' was already taken.",
    GameCancelled: "Game was cancelled because opponent has left.",
    StartGameError: "Game failed to start. Please try again later.",
    OpponentInAnotherGame:
      (error.arg ? error.arg : "Opponent") +
      " is playing another game. Please try again later.",
    RegisterError: "Game failed to register. Please try again later.",
    PlayerNotFound: "Player has not registered."
  };
  let msg = msgs[error.code];
  return msg ? msg : "An internal error has occurred.";
}

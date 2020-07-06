import reversi from "ic:canisters/reversi";
import reversi_assets from "ic:canisters/reversi_assets";
import "./style.css";

// The sound of putting down a piece. It will be loaded from reversi_assets.
var putsound = null;

// Play a sound.
function playAudio(sound) {
  if ("buffer" in sound) {
    var audioSource = sound.context.createBufferSource();
    audioSource.connect(sound.context.destination);
    audioSource.buffer = sound.buffer;
    if (audioSource.noteOn) {
      audioSource.noteOn(0);
    } else {
      audioSource.start();
    }
  }
}

const clientRatio =
  document.documentElement.clientWidth / document.documentElement.clientHeight;

const factor = clientRatio > 0.8 ? 0.75 : 0.9;

// The length (and width) of the reversi board.
const boardLength =
  Math.min(
    document.documentElement.clientWidth,
    document.documentElement.clientHeight
  ) * factor;

//////////////////////////////////////////////////////////////////////////////
// Game logic (Copied from Motoko code)
// We use '*' for black and 'O' for white.
//////////////////////////////////////////////////////////////////////////////

// Return the opponent color.
function opponent(color) {
  return color == "*" ? "O" : "*";
}

// Check if a piece of the given color exists on the board using
// coordinate (i, j) and offset (p, q).
function exists(N, board, color, i, j, p, q) {
  let s = i + p;
  let t = j + q;
  return s >= 0 && s < N && t >= 0 && t < N && board[s * N + t] == color;
}

// Check if a piece of the given color eventually exits on the board
// using coordinate (i, j) and direction (p, q), ignoring opponent colors
// in between. Return false if the given color is not found before reaching
// empty cell or board boundary.
function eventually(N, board, color, i, j, p, q) {
  if (exists(N, board, opponent(color), i, j, p, q)) {
    return eventually(N, board, color, i + p, j + q, p, q);
  } else {
    return exists(N, board, color, i, j, p, q);
  }
}

// Return true if a valid move is possible for color at the given position (i, j).
function validMove(N, board, color, i, j) {
  for (var p = -1; p <= 1; p++) {
    for (var q = -1; q <= 1; q++) {
      if (!(p == 0 && q == 0)) {
        if (
          exists(N, board, opponent(color), i, j, p, q) &&
          eventually(N, board, color, i, j, p, q)
        ) {
          return true;
        }
      }
    }
  }
  return false;
}

// Calculate the number of validate next move for a given color.
function validMoves(N, board, color) {
  var count = 0;
  for (var p = -1; p <= 1; p++) {
    for (var q = -1; q <= 1; q++) {
      if (board[i * N + j] == "." && valid_move(N, board, color, i, j)) {
        count += 1;
      }
    }
  }
  return count;
}

// Flip pieces of opponent color into the given color starting from
// coordinate (i, j) and along direction (p, q).
function flip(N, board, color, i, j, p, q) {
  if (exists(N, board, opponent(color), i, j, p, q)) {
    let s = i + p;
    let t = j + q;
    board[s * N + t] = color;
    flip(N, board, color, s, t, p, q);
  }
}

// Set a piece on the board at a given position, and flip all
// affected opponent pieces accordingly. It requires that the
// given position is a valid move before this call.
function set_and_flip(N, board, color, i, j) {
  board[i * N + j] = color;
  for (var p = -1; p <= 1; p++) {
    for (var q = -1; q <= 1; q++) {
      if (!(p == 0 && q == 0)) {
        if (
          exists(N, board, opponent(color), i, j, p, q) &&
          eventually(N, board, color, i, j, p, q)
        ) {
          flip(N, board, color, i, j, p, q);
        }
      }
    }
  }
  return board;
}

// Given a sequence of moves, replay the board.
function replay(N, moves) {
  var board = new Array(N * N);
  for (var i = 0; i < N * N; i++) {
    board[i] = ".";
  }
  var color = "O";
  for (var k = 0; k < moves.length; k++) {
    const idx = moves[k];
    const i = Math.floor(idx / N);
    const j = idx % N;
    if (k < 4) {
      board[idx] = color;
    } else if (validMove(N, board, color, i, j)) {
      set_and_flip(N, board, color, i, j);
    } else {
      color = opponent(color);
      set_and_flip(N, board, color, i, j);
    }
    color = opponent(color);
  }
  return board;
}

function same_color(color1, color2) {
  return (
    ("black" in color1 && "black" in color2) ||
    ("white" in color1 && "white" in color2)
  );
}

//////////////////////////////////////////////////////////////////////////////
// UI logic
//////////////////////////////////////////////////////////////////////////////

var animateTimeout = null;

// Draw the board in SVG.
function Board(player_color, next_color, game, boards, onClick, onDismiss) {
  console.log("redraw board");
  const white_id = game["white"][0];
  const black_id = game["black"][0];
  const white_player = game["white"][1];
  const black_player = game["black"][1];
  const dimension = game.dimension.toNumber();
  const last = boards.length > 1 ? boards.shift() : null;
  const board = boards[0];
  const animate_list = [];
  // const next = game["next"];

  const dot_start = "white" in next_color ? boardLength - 90 : 10;
  const dot_color = "white" in next_color ? "#fff" : "#000";
  let dots = [];
  let dotsHeight = 20;
  // Only draw dots if result is not out yet
  if (game["result"].length == 0) {
    for (var i = 0; i < 5; i++) {
      dots.push(
        m(
          "circle.dot",
          {
            cx: dot_start + i * 20,
            cy: dotsHeight / 2,
            r: 6,
            fill: dot_color
          },
          m("animate", {
            attributeName: "opacity",
            dur: "2s",
            values: "0;1;0",
            repeatCount: "indefinite",
            begin: 0.3 + i * 0.3,
            restart: "whenNotActive"
          })
        )
      );
    }
  }

  const cellSize = Math.floor(boardLength / dimension);
  let cells = [];
  cells.push(
    m("defs", [
      m("filter", { id: "shadow" }, [
        m("feDropShadow", { dx: 2, dy: 4, stdDeviation: 0.5 })
      ])
    ])
  );

  const my_piece = "black" in player_color ? "*" : "O";
  let hintColor = my_piece == "O" ? "#ddd" : "#000";
  let hintOn = same_color(player_color, next_color);
  for (var row = 0; row < dimension; row++) {
    for (var col = 0; col < dimension; col++) {
      const idx = row * dimension + col;
      const value = board[idx];
      const nextMove =
        hintOn && validMove(dimension, board, my_piece, row, col);
      let attrs = {
        x: col * cellSize,
        y: row * cellSize,
        width: cellSize,
        height: cellSize,
        style: {
          fill: "#060",
          stroke: "#000",
          strokeWidth: 1
        },
        id: row * dimension + col
      };
      if (value == "." && nextMove) {
        attrs["onclick"] = onClick;
      }
      cells.push(m("rect", attrs));

      if (value == ".") {
        // if valid move is possible at (row, col), draw dotted circle.
        if (nextMove) {
          cells.push(
            m("circle", {
              cx: col * cellSize + cellSize * 0.5,
              cy: row * cellSize + cellSize * 0.5,
              r: cellSize * 0.4,
              stroke: hintColor,
              "stroke-dasharray": 4,
              "stroke-width": 1,
              "stroke-opacity": 0.6,
              fill: "none"
            })
          );
        }
      } else {
        const pieceColor = value == "O" ? "#fff" : "#000";
        const opponentColor = value == "O" ? "#000" : "#fff";
        const strokeColor = value == "O" ? "#333" : "#888";
        var elems = [];
        if (last != null && last[row * dimension + col] != value) {
          if (last[row * dimension + col] == ".") {
            // elem = value == "O" ? "empty-white" : "empty-black";
            elems.push(
              m("animate", {
                attributeName: "rx",
                dur: "0.2s",
                repeatCount: "1",
                from: cellSize * 0.1,
                to: cellSize * 0.4,
                restart: "whenNotActive"
              })
            );
            elems.push(
              m("animate", {
                attributeName: "ry",
                dur: "0.2s",
                repeatCount: "1",
                from: cellSize * 0.1,
                to: cellSize * 0.4,
                restart: "whenNotActive"
              })
            );
            animate_list.push("animate-" + (row * dimension + col));
            console.log("animate");
          } else {
            //elem = value == "O" ? "black-white" : "white-black";
            elems.push(
              m("animate", {
                attributeName: "rx",
                dur: "0.2s",
                repeatCount: "1",
                values: cellSize * 0.4 + ";0;" + cellSize * 0.4,
                restart: "whenNotActive"
              })
            );
            elems.push(
              m("animate", {
                attributeName: "fill",
                dur: "0.2s",
                repeatCount: "1",
                values: opponentColor + ";" + pieceColor,
                restart: "whenNotActive"
              })
            );
          }
        }
        cells.push(
          m(
            "ellipse",
            {
              cx: col * cellSize + cellSize * 0.5,
              cy: row * cellSize + cellSize * 0.5,
              rx: cellSize * 0.4,
              ry: cellSize * 0.4,
              stroke: strokeColor,
              "stroke-width": 2,
              "stroke-opacity": 0.4,
              fill: pieceColor,
              filter: "url(#shadow)"
            },
            elems
          )
        );
      }
    }

    if (game["result"].length != 0) {
      cells.push(
        m("rect", {
          x: boardLength / 8,
          y: boardLength / 4,
          width: (boardLength * 3) / 4,
          height: boardLength / 2,
          style: {
            fill: "#685",
            stroke: "#000",
            strokeWidth: 3
          },
          onclick: onDismiss
        })
      );
      cells.push(
        m(
          "text.score",
          {
            x: "50%",
            y: "50%",
            "dominant-baseline": "middle",
            "text-anchor": "middle"
          },
          [
            m(
              "tspan",
              {
                fill: "black"
              },
              game.result[0]["black"].toNumber()
            ),
            "   :   ",
            m(
              "tspan",
              {
                fill: "white"
              },
              game.result[0]["white"].toNumber()
            )
          ]
        )
      );
    }

    clearTimeout(animateTimeout);
    if (animate_list) {
      animateTimeout = setTimeout(function() {
        document.querySelectorAll("animate").forEach(animate => {
          animate.beginElement();
        });
      }, 0);
    }
  }

  return [
    m("div.players", { style: { width: boardLength + "px" } }, [
      m("span.black-player", black_player),
      m("span.white-player", white_player)
    ]),
    m("svg.dots", { width: boardLength, height: dotsHeight }, dots),
    m("svg.board", { width: boardLength, height: boardLength }, cells),
    m("h1.dimension", dimension + " × " + dimension)
  ];
}

// Color coresponds to Motoko variant type {#black; #white}.
const black = { black: null };
const white = { white: null };

function flipColor(color) {
  return "black" in color ? white : black;
}

function get_error_message(err) {
  let msgs = {
    NoSelfGame: "Please input an opponent other than yourself.",
    InvalidName:
      "Name must be alphanumerical with no space, and between 3 and 10 characters long.",
    InvalidOpponentName:
      "Opponent name must be alphanumerical with no space, and between 3 and 10 characters long.",
    NameAlreadyExists: "Name already taken by another player.",
    GameCancelled: "Game was cancelled because the opponent has left.",
    StartGameError: "Game failed to start. Please try again later.",
    RegisterError: "Game failed to register. Please try again later."
  };
  let msg = msgs[err];
  return msg ? msg : "An internal error has occurred.";
}

// The refresh timeout is global, because we want to stop it in non-game compnent.
var refreshTimeout = null;

// The error code is global to avoid showing up in the URL
var error_code = null;

// Main game UI component.
function Game() {
  var game = null;
  var boards = [];
  var last_move_length = null;
  var player_color = null;
  var next_color = null;
  var refresh = function() {
    clearTimeout(refreshTimeout);
    reversi
      .view()
      .then(res => {
        console.log("refresh view");
        //console.log(res);
        if (res.length == 0) {
          error_code = "GameCancelled";
          m.route.set("/play");
        } else {
          game = res[0];
          if (game.moves.length > last_move_length) {
            let opponent_piece = "white" in player_color ? "*" : "O";
            const N = game.dimension.toNumber();
            while (last_move_length < game.moves.length) {
              playAudio(putsound);
              const idx = game.moves[last_move_length];
              const i = Math.floor(idx / N);
              const j = idx % N;
              var board = Array.from(boards[boards.length - 1]);
              set_and_flip(N, board, opponent_piece, i, j);
              boards.push(board);
              last_move_length += 1;
            }
            let matched = game.board == board.join("");
            console.log("board match " + matched);
            if (!matched) {
              console.log("game board: " + game.board);
              console.log("my   board: " + board.join(""));
            }
            m.redraw();
          } else if (game.result.length > 0) {
            m.redraw();
          } else if (
            game.moves.length == last_move_length &&
            !same_color(next_color, game.next)
          ) {
            next_color = game.next;
            m.redraw();
          }
          refreshTimeout = setTimeout(refresh, 1000);
        }
      })
      .catch(function(err) {
        console.log("view error, will try again.");
        console.log(err);
        refresh();
      });
  };
  var start = function(player, opponent) {
    if (putsound === null) {
      putsound = {}; // avoid loading it twice
      reversi_assets
        .retrieve("put.mp3")
        .then(array => {
          let buffer = new Uint8Array(array);
          var context = new AudioContext();
          context.decodeAudioData(buffer.buffer, function(res) {
            console.log("Audio is loaded");
            putsound = { buffer: res, context: context };
          });
        })
        .catch(function(err) {
          console.log("asset retrieve error, ignore");
          console.log(err);
        });
    }
    console.log("start " + player + " against " + opponent);
    reversi
      .start(opponent)
      .then(res => {
        console.log("start res = " + JSON.stringify(res));
        if ("ok" in res) {
          game = res["ok"];
          const N = game.dimension.toNumber();
          var board = replay(N, game.moves);
          boards.push(board);
          last_move_length = game.moves.length;
          console.log("start game " + JSON.stringify(game));
          player_color = game.white[1] == player ? white : black;
          next_color = game.next;
          m.redraw();
          refresh();
        } else if ("PlayerNotFound" in res["err"]) {
          // maybe name was reversed? try again from play UI.
          m.route.set("/play", { player: opponent, opponent: player });
        } else {
          error_code = Object.keys(res["err"])[0];
          m.route.set("/play");
        }
      })
      .catch(function(err) {
        console.log("start error");
        console.log(err);
        error_code = "StartGameError";
        m.route.set("/play");
      });
  };

  var next_move = function(evt) {
    const dimension = game.dimension.toNumber();
    const idx = parseInt(evt.target.id);
    const row = Math.floor(idx / dimension);
    const col = idx % dimension;
    playAudio(putsound);
    console.log(JSON.stringify(player_color) + " move " + row + ", " + col);
    const piece = "white" in player_color ? "O" : "*";
    var board = boards[boards.length - 1];
    if (
      same_color(player_color, next_color) &&
      validMove(dimension, board, piece, row, col)
    ) {
      last_move_length += 1;
      board = Array.from(board);
      set_and_flip(dimension, board, piece, row, col);
      boards.push(board);
      next_color = flipColor(player_color);
      reversi
        .move(row, col)
        .then(res => {
          if ("OK" in res || "Pass" in res || "GameOver" in res) {
          } else {
            console.log(JSON.stringify(res));
          }
        })
        .catch(function(err) {
          console.log("move error, ignore");
          console.log(err);
        });
    }
    m.redraw();
  };
  return {
    onremove: function(vnode) {
      clearTimeout(refreshTimeout);
    },
    view: function(vnode) {
      var content;
      if (game === null) {
        let opponent = vnode.attrs.against;
        if (opponent[0] == ".") {
          opponent = opponent.substring(1);
        }
        start(vnode.attrs.player, opponent);
        content = m("div");
      } else {
        content = Board(
          player_color,
          next_color,
          game,
          boards,
          next_move,
          function(e) {
            m.route.set("/play");
          }
        );
      }
      return m("div", content);
    }
  };
}

// these are global because we want to come back to /play remembering previous settings.
var inited = null;
var player_name = null;
var player_score = null;

// Play screen UI component.
function Play() {
  var opponent_name = null;
  var set_player_info = function(info) {
    player_name = info["name"];
    player_score = info["score"].toNumber();
  };
  var init_play = function() {
    if (refreshTimeout) {
      clearTimeout(refreshTimeout);
    }
    reversi
      .register("")
      .then(res => {
        inited = true;
        console.log("init_play: " + JSON.stringify(res));
        if ("ok" in res) {
          set_player_info(res["ok"]);
        }
        m.redraw();
      })
      .catch(function(err) {
        console.log("register error");
        console.log(err);
        error_code = "RegisterError";
        m.route.set("/play");
      });
  };
  var play = function(e) {
    e.preventDefault();
    // clear error code on submit
    error_code = null;
    console.log(player_name + " against " + opponent_name);
    reversi
      .register(player_name)
      .then(res => {
        if ("ok" in res) {
          set_player_info(res["ok"]);
          m.route.set("/game/:player/:against", {
            player: player_name.trim(),
            against: "." + opponent_name.trim()
          });
        } else {
          error_code = Object.keys(res["err"])[0];
          m.route.set("/play");
        }
      })
      .catch(function(err) {
        console.log("register error");
        console.log(err);
        error_code = "RegisterError";
        m.route.set("/play");
      });
  };
  return {
    oninit: init_play,
    view: function(vnode) {
      if (vnode.attrs.player && player_name == null) {
        player_name = vnode.attrs.player;
      }
      if (vnode.attrs.opponent && opponent_name == null) {
        opponent_name = vnode.attrs.opponent;
      }
      if (inited) {
        var title = "Welcome to Reversi!";
        var score = m("h2");
        var form = [];
        var error_msg = error_code ? get_error_message(error_code) : "";

        if (player_score === null) {
          form.push(
            m("input.input[type=text][placeholder=Your name]", {
              oninput: function(e) {
                player_name = e.target.value;
              },
              value: player_name
            })
          );
        } else {
          title = "Welcome back to Reversi, " + player_name + "!";
          score = m("h2", [
            m("span", "Your Score: "),
            m("span.total_score", player_score)
          ]);
        }
        form.push(
          m("input.input[placeholder=Opponent name]", {
            oninput: function(e) {
              opponent_name = e.target.value;
            },
            value: opponent_name
          })
        );
        form.push(m("button.button[type=submit]", "Play!"));
        return m(
          "div.centered",
          m("div.cover", [
            m("h1", title),
            score,
            m("div.error", error_msg),
            m("form", { onsubmit: play }, form)
          ])
        );
      }
    }
  };
}

var m = require("mithril");
m.route(document.body, "/play", {
  "/play": Play,
  "/game/:player/:against": Game
});

/*
score calculation
*/

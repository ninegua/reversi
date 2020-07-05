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

// The length (and width) of the reversi board.
const boardLength =
  Math.min(
    document.documentElement.clientWidth,
    document.documentElement.clientHeight
  ) * 0.75;

// The height of the display area above the board.
const displayHeight = boardLength / 5;

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

//////////////////////////////////////////////////////////////////////////////
// UI logic
//////////////////////////////////////////////////////////////////////////////

// Draw the board in SVG.
function Board(player_color, game, onClick, onDismiss) {
  const white_id = game["white"][0];
  const black_id = game["black"][0];
  const white_player = game["white"][1];
  const black_player = game["black"][1];
  const board = game["board"];
  const dimension = game.dimension.toNumber();
  const next = game["next"];

  let display = [
    m(
      "text.black",
      {
        x: 0,
        y: displayHeight / 2,
        "text-anchor": "start",
        "dominant-baseline": "middle"
      },
      black_player
    ),
    m(
      "text.white",
      {
        x: boardLength,
        y: displayHeight / 2,
        "text-anchor": "end",
        "dominant-baseline": "middle"
      },
      white_player
    )
  ];

  const dot_start = "white" in next ? boardLength - 90 : 10;
  const dot_color = "white" in next ? "#fff" : "#000";

  // Only draw dots if result is not out yet
  if (game["result"].length == 0) {
    for (var i = 0; i < 5; i++) {
      display.push(
        m(
          "circle.dot",
          {
            cx: dot_start + i * 20,
            cy: (displayHeight * 7) / 8,
            r: 6,
            fill: dot_color
          },
          m("animate", {
            attributeName: "opacity",
            dur: "2s",
            values: "0;1;0",
            repeatCount: "indefinite",
            begin: 0.3 + i * 0.3
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
  let hintOn =
    ("black" in player_color && "black" in next) ||
    ("white" in player_color && "white" in next);
  for (var row = 0; row < dimension; row++) {
    for (var col = 0; col < dimension; col++) {
      const idx = row * dimension + col;
      const value = board.charAt(idx);
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
        const strokeColor = value == "O" ? "#333" : "#888";
        cells.push(
          m("circle", {
            cx: col * cellSize + cellSize * 0.5,
            cy: row * cellSize + cellSize * 0.5,
            r: cellSize * 0.4,
            stroke: strokeColor,
            "stroke-width": 2,
            "stroke-opacity": 0.4,
            fill: pieceColor,
            filter: "url(#shadow)"
          })
        );
      }
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
        "text",
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
  return [
    m("svg", { width: boardLength, height: displayHeight }, display),
    m("svg", { width: boardLength, height: boardLength }, cells)
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
var timeout = null;

// Main game UI component.
function Game() {
  var game = null;
  var color = white;
  var refresh = function() {
    clearTimeout(timeout);
    reversi
      .view()
      .then(res => {
        console.log("refresh view " + JSON.stringify(res));
        if (res.length == 0) {
          m.route.set("/play", { err: "GameCancelled" });
        } else {
          game = res[0];
          m.redraw();
          timeout = setTimeout(refresh, 1000);
        }
      })
      .catch(function(err) {
        console.log("view error, will try again.");
        console.log(err);
        refresh();
      });
  };
  var start_game = function(player, opponent) {
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
    console.log("start_game " + player + " against " + opponent);
    reversi
      .start_game(opponent)
      .then(res => {
        console.log("start_game res = " + JSON.stringify(res));
        if ("ok" in res) {
          game = res["ok"];
          console.log("start game " + JSON.stringify(game));
          color = game.white[1] == player ? white : black;
          m.redraw();
          refresh();
        } else if ("PlayerNotFound" in res["err"]) {
          // maybe name was reversed? try again from play UI.
          clearTimeout(timeout);
          m.route.set("/play", { player: opponent, opponent: player });
        } else {
          let err = Object.keys(res["err"])[0];
          clearTimeout(timeout);
          m.route.set("/play", { err: err });
        }
      })
      .catch(function(err) {
        console.log("start_game error");
        console.log(err);
        m.route.set("/play", { err: "StartGameError" });
      });
  };

  var next_move = function(evt) {
    const dimension = game.dimension.toNumber();
    const idx = parseInt(evt.target.id);
    const row = Math.floor(idx / dimension);
    const col = idx % dimension;
    playAudio(putsound);
    console.log(JSON.stringify(color) + " move " + row + ", " + col);
    reversi
      .move(row, col)
      .then(res => {
        if ("OK" in res || "Pass" in res || "GameOver" in res) {
          refresh();
        } else {
          console.log(JSON.stringify(res));
        }
      })
      .catch(function(err) {
        console.log("move error, ignore");
        console.log(err);
      });
  };
  return {
    onremove: function(vnode) {
      clearTimeout(timeout);
    },
    view: function(vnode) {
      var content;
      if (game === null) {
        let opponent = vnode.attrs.against;
        if (opponent[0] == ".") {
          opponent = opponent.substring(1);
        }
        start_game(vnode.attrs.player, opponent);
        content = m("div");
      } else {
        content = Board(color, game, next_move, function(e) {
          clearTimeout(timeout);
          m.route.set("/play");
        });
      }
      return m("div", content);
    }
  };
}

// these are global because we want to come back to /play remembering previous settings.
var inited = null;
var player_name = "";
var player_score = null;

// Play screen UI component.
function Play() {
  var opponent_name = "";
  var set_player_info = function(info) {
    player_name = info["name"];
    player_score = info["score"].toNumber();
  };
  var init_play = function() {
    if (timeout) {
      clearTimeout(timeout);
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
        m.route.set("/play", { err: "RegisterError" });
      });
  };
  var play = function(e) {
    e.preventDefault();
    console.log(player_name + " against " + opponent_name);
    reversi
      .register(player_name)
      .then(res => {
        if ("ok" in res) {
          set_player_info(res["ok"]);
          console.log("route.set game/:player/:againt");
          m.route.set("/game/:player/:against", {
            player: player_name,
            against: "." + opponent_name
          });
        } else {
          let err = Object.keys(res["err"])[0];
          m.route.set("/play", { err: err });
        }
      })
      .catch(function(err) {
        console.log("register error");
        console.log(err);
        m.route.set("/play", { err: "RegisterError" });
      });
  };
  return {
    oninit: init_play,
    view: function(vnode) {
      if (vnode.attrs.player && player_name == "") {
        player_name = vnode.attrs.player;
      }
      if (vnode.attrs.opponent && opponent_name == "") {
        opponent_name = vnode.attrs.opponent;
      }
      if (inited) {
        var title = "Welcome to Reversi!";
        var score = m("h2");
        var form = [];
        if ("err" in vnode.attrs) {
          let msg = get_error_message(vnode.attrs.err);
          form.push(m("label.error", msg));
        }
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
            m("span.total_scoure", player_score)
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
        return m("div", { style: { width: boardLength + "px" } }, [
          m("h1", title),
          score,
          m("form", { onsubmit: play }, form)
        ]);
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

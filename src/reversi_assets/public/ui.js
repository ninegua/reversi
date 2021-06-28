//////////////////////////////////////////////////////////////////////////////
// Sound and graphics helper functions
//////////////////////////////////////////////////////////////////////////////
import { valid_move } from "./game.js";
import m from "mithril";

// The sound of putting down a piece. It will be loaded from reversi_assets.
var putsound = null;

export function play_put_sound() {
  playAudio(putsound);
}

export function load_put_sound(reversi_assets) {
  if (putsound === null) {
    putsound = {}; // avoid loading it twice
    fetch("/put.mp3")
      .then(function (response) {
        return response.arrayBuffer();
      })
      .then(function (buffer) {
        var context = new AudioContext();
        context.decodeAudioData(buffer, function (res) {
          //console.log("Audio is loaded");
          putsound = { buffer: res, context: context };
        });
      })
      .catch(function (err) {
        console.log("Asset retrieve error, ignore");
        console.log(err);
      });
  }
}

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
// UI logic
//////////////////////////////////////////////////////////////////////////////

var animateTimeout = null;

export function get_player_name(player) {
  return player.PlayerName ? player.PlayerName : player.Player[1].name;
}

// Draw the board in SVG.
export function Board(
  message,
  player_color,
  next_color,
  game,
  boards,
  onClick,
  onDismiss
) {
  const white_player = get_player_name(game.white);
  const black_player = get_player_name(game.black);
  const dimension = Number(game.dimension);
  const last = boards.length > 1 ? boards[0].board : null;
  const board = boards.length > 1 ? boards[1].board : boards[0].board;
  const animate_list = [];
  console.log("Redraw board " + boards.length);

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
            fill: dot_color,
          },
          m("animate", {
            attributeName: "opacity",
            dur: "2s",
            values: "0;1;0",
            repeatCount: "indefinite",
            begin: 0.3 + i * 0.3,
            restart: "whenNotActive",
            id: "dot-" + i,
          })
        )
      );
    }
  }

  const cellSize = Math.floor(boardLength / dimension);
  let cells = [];
  cells.push(
    m("defs", [
      m("filter", { id: "shadow-0" }, [
        m("feDropShadow", { dx: 2, dy: 4, stdDeviation: 0.5 }),
      ]),
      m("filter", { id: "shadow-45" }, [
        m("feDropShadow", { dx: 4.22, dy: 1.46, stdDeviation: 0.5 }),
      ]),
      m("filter", { id: "shadow-90" }, [
        m("feDropShadow", { dx: 4, dy: -2, stdDeviation: 0.5 }),
      ]),
      m("filter", { id: "shadow-135" }, [
        m("feDropShadow", { dx: 1.46, dy: -4.22, stdDeviation: 0.5 }),
      ]),
    ])
  );

  const my_piece = "black" in player_color ? "*" : "O";
  let hintColor = my_piece == "O" ? "#ddd" : "#000";
  let hintOn = same_color(player_color, next_color);
  let hintStrokeWidth = my_piece == "O" ? 1 : 2;
  for (var row = 0; row < dimension; row++) {
    for (var col = 0; col < dimension; col++) {
      const idx = row * dimension + col;
      const value = board[idx];
      const nextMove =
        hintOn && valid_move(dimension, board, my_piece, row, col);
      let attrs = {
        x: col * cellSize,
        y: row * cellSize,
        width: cellSize,
        height: cellSize,
        style: {
          fill: "#060",
          stroke: "#000",
          strokeWidth: 1,
        },
        id: idx,
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
              "stroke-width": hintStrokeWidth,
              "stroke-opacity": 0.6,
              fill: "none",
            })
          );
        }
      } else {
        let pieceColor = value == "O" ? "#fff" : "#000";
        let opponentColor = value == "O" ? "#000" : "#fff";
        let strokeColor = value == "O" ? "#333" : "#888";
        let elems = [];
        let radius = cellSize * 0.4;
        let degree = 0;
        if (last != null && last[idx] != value) {
          //console.log([row, col, last[idx], value]);
          if (last[idx] == ".") {
            elems.push(
              m("animate", {
                attributeName: "rx",
                begin: "indefinite",
                dur: "0.2s",
                repeatCount: "1",
                from: cellSize * 0.1,
                to: radius,
                fill: "freeze",
              })
            );
            elems.push(
              m("animate", {
                attributeName: "ry",
                begin: "indefinite",
                dur: "0.2s",
                repeatCount: "1",
                from: cellSize * 0.1,
                to: radius,
                fill: "freeze",
              })
            );
            radius = cellSize * 0.1;
            animate_list.push("animate-" + idx);
          } else {
            elems.push(
              m("animate", {
                attributeName: "rx",
                begin: "indefinite",
                dur: "0.4s",
                repeatCount: "1",
                values: [radius, radius, "0", radius].join(";"),
                fill: "freeze",
              })
            );
            elems.push(
              m("animate", {
                attributeName: "fill",
                begin: "indefinite",
                dur: "0.4s",
                repeatCount: "1",
                values: [opponentColor, opponentColor, "#888", pieceColor].join(
                  ";"
                ),
                fill: "freeze",
              })
            );
            pieceColor = opponentColor;
            let dy = boards[1].row - row;
            let dx = boards[1].col - col;
            if (dx == 0) {
              degree = 90;
            } else if (dy == 0) {
              degree = 0;
            } else if (dx < 0) {
              degree = dy > 0 ? 135 : 45;
            } else {
              degree = dy > 0 ? 45 : 135;
            }
          }
        }
        const cx = col * cellSize + cellSize * 0.5;
        const cy = row * cellSize + cellSize * 0.5;
        cells.push(
          m(
            "ellipse.no-flicker",
            {
              cx: cx,
              cy: cy,
              rx: radius,
              ry: radius,
              stroke: strokeColor,
              "stroke-width": 2,
              "stroke-opacity": 0.4,
              fill: pieceColor,
              filter: "url(#shadow-" + degree + ")",
              transform: "rotate(" + degree + " " + cx + " " + cy + ")",
            },
            elems
          )
        );
      }
    }
  }

  // Show game result if it has ended
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
          strokeWidth: 3,
        },
        onclick: onDismiss,
      })
    );
    cells.push(
      m(
        "text.score",
        {
          x: "50%",
          y: "50%",
          "dominant-baseline": "middle",
          "text-anchor": "middle",
        },
        [
          m("tspan", { fill: "black" }, Number(game.result[0]["black"])),
          "   :   ",
          m("tspan", { fill: "white" }, Number(game.result[0]["white"])),
        ]
      )
    );
  }

  // Need to kick start animate element for svg, otherwise animation
  // will only show once and then stop running, even when new animate
  // elements are created. This is likely due to mithril caching, not
  // sure if there is an alternative work-around.
  clearTimeout(animateTimeout);
  if (animate_list) {
    animateTimeout = setTimeout(function () {
      document.querySelectorAll("animate").forEach(function (animate) {
        if (!animate.id.startsWith("dot")) {
          animate.beginElement();
        }
      });
      setTimeout(function () {
        if (boards.length > 1) {
          boards.shift();
          if (boards.length > 1) {
            m.redraw();
          }
        }
      }, 300);
    }, 0);
  } else {
    if (boards.length > 1) {
      boards.shift();
      if (boards.length > 1) {
        m.redraw();
      }
    }
  }

  return [
    m("div.players", { style: { width: boardLength + "px" } }, [
      m("span.black-player", black_player),
      m("span.white-player", white_player),
    ]),
    m("svg.dots", { width: boardLength, height: dotsHeight }, dots),
    m("svg.board", { width: boardLength, height: boardLength }, cells),
    message == ""
      ? m("h2.dimension", dimension + " × " + dimension)
      : m("h2.blink", message),
  ];
}

// Color coresponds to Motoko variant type {#black; #white}.
export const black = { black: null };
export const white = { white: null };

export function same_color(color1, color2) {
  return (
    ("black" in color1 && "black" in color2) ||
    ("white" in color1 && "white" in color2)
  );
}

export function opponent_color(color) {
  return "black" in color ? white : black;
}

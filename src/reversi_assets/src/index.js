import { Ed25519KeyIdentity } from "@dfinity/identity";
import { Actor, HttpAgent } from "@dfinity/agent";
import {
  idlFactory as reversi_idl,
  canisterId as reversi_id,
} from "../../declarations/reversi";
import {
  idlFactory as reversi_assets_idl,
  canisterId as reversi_assets_id,
} from "../../declarations/reversi_assets";

String.prototype.equalIgnoreCase = function (str) {
  return (
    str != null &&
    typeof str === "string" &&
    this.toUpperCase() === str.toUpperCase()
  );
};

function newIdentity() {
  const entropy = crypto.getRandomValues(new Uint8Array(32));
  const identity = Ed25519KeyIdentity.generate(entropy);
  localStorage.setItem("reversi_id", JSON.stringify(identity));
  return identity;
}

function readIdentity() {
  const stored = localStorage.getItem("reversi_id");
  if (!stored) {
    return newIdentity();
  }
  try {
    return Ed25519KeyIdentity.fromJSON(stored);
  } catch (error) {
    console.log(error);
    return newIdentity();
  }
}
const identity = readIdentity();
const player_id = identity.getPrincipal().toHex();
const agent = new HttpAgent({ identity });

const reversi = Actor.createActor(reversi_idl, {
  agent,
  canisterId: reversi_id,
});
const reversi_assets = Actor.createActor(reversi_assets_idl, {
  agent,
  canisterId: reversi_assets_id,
});

import { valid_move, set_and_flip, replay } from "./game.js";
import { get_error_message, set_error, clear_error } from "./error.js";
import {
  Board,
  black,
  white,
  same_color,
  opponent_color,
  play_put_sound,
  load_put_sound,
  get_player_name,
} from "./ui.js";
import "./style.css";
import logo from "./logo.png";
import m from "mithril";

document.title = "Reversi Game on IC";

// Create a spinner overlay
const spinner_overlay = document.createElement("div");
spinner_overlay.id = "spinner_overlay";
const spinner = document.createElement("div");
spinner.id = "spinner";
spinner_overlay.appendChild(spinner);
const main = document.createElement("div");
main.id = "main";
document.body.appendChild(spinner_overlay);
document.body.appendChild(main);
function start_loading() {
  spinner_overlay.style.display = "block";
}
function stop_loading() {
  spinner_overlay.style.display = "none";
}

// The refresh timeout is global, because we want to stop it in non-game compnent too.
var refreshTimeout = null;

function toJSON(obj) {
  return JSON.stringify(obj, (key, value) =>
    typeof value === "bigint" ? value.toString() : value
  );
}

// Main game UI component.
function Game() {
  var game = null;
  var boards = [];
  var last_move_length = null;
  var player_color = null;
  var next_color = null;
  var expiring = null;
  var refresh = function () {
    clearTimeout(refreshTimeout);
    reversi
      .view()
      .then(function (res) {
        // console.log("refresh view");
        // console.log(res);
        if (res.length == 0) {
          set_error("GameCancelled");
          start_loading();
          m.route.set("/play");
        } else {
          if (expiring) {
            if (new Date() - expiring > 1000 * 60) {
              set_error("GameCancelled");
              start_loading();
              m.route.set("/play");
              return;
            }
          } else if (game.expiring) {
            expiring = new Date();
            m.redraw();
          }
          let black_name = game ? get_player_name(game.black) : null;
          let white_name = game ? get_player_name(game.white) : null;
          game = res[0];
          if (game.moves.length > last_move_length) {
            // handle new moves
            let opponent_piece = "white" in player_color ? "*" : "O";
            const N = Number(game.dimension);
            while (last_move_length < game.moves.length) {
              play_put_sound();
              const idx = game.moves[last_move_length];
              const i = Math.floor(idx / N);
              const j = idx % N;
              var board = Array.from(boards[boards.length - 1].board);
              set_and_flip(N, board, opponent_piece, i, j);
              boards.push({ row: i, col: j, board: board });
              last_move_length += 1;
            }
            let matched = game.board == board.join("");
            if (!matched) {
              console.log("CRITICAL ERROR!!!");
              console.log("Game  board: " + game.board);
              console.log("Local board: " + board.join(""));
            }
            m.redraw();
          } else if (game.result.length > 0) {
            // handle end of game
            m.redraw();
          } else if (
            game.moves.length == last_move_length &&
            !same_color(next_color, game.next)
          ) {
            // redraw when next player has changed
            next_color = game.next;
            m.redraw();
          } else if (
            !black_name.equalIgnoreCase(get_player_name(game.black)) ||
            !white_name.equalIgnoreCase(get_player_name(game.white))
          ) {
            if (
              get_player_name(game.white) == "" ||
              get_player_name(game.black) == ""
            ) {
              // player left, we'll terminate
              set_error("GameCancelled");
              start_loading();
              m.route.set("/play");
              return;
            } else {
              // reset game when player name has changed
              const N = Number(game.dimension);
              var board = replay(N, game.moves);
              boards = [{ row: -1, col: -1, board: board }];
              m.redraw();
            }
          }
          refreshTimeout = setTimeout(refresh, 1000);
        }
      })
      .catch(function (err) {
        console.log("View error, will try again.");
        console.log(err);
        refresh();
      });
  };
  var start = function (player, opponent) {
    clearTimeout(refreshTimeout);
    load_put_sound(reversi_assets);
    console.log("Start " + player + " against " + opponent);
    reversi
      .start(opponent)
      .then(function (res) {
        //console.log("start res = " + toJSON(res));
        if ("ok" in res) {
          stop_loading();
          game = res["ok"];
          const N = Number(game.dimension);
          var board = replay(N, game.moves);
          boards.push({ row: -1, col: -1, board: board });
          last_move_length = game.moves.length;
          //console.log("start game " + toJSON(game));
          player_color = player.equalIgnoreCase(get_player_name(game.white))
            ? white
            : black;
          next_color = game.next;
          m.redraw();
          refresh();
        } else if ("PlayerNotFound" in res["err"]) {
          // maybe name was reversed? try again from play UI.
          start_loading();
          m.route.set("/play", { player: opponent, opponent: player });
        } else {
          let error_code = Object.keys(res["err"])[0];
          set_error(
            error_code,
            error_code == "OpponentInAnotherGame" ? opponent : null
          );
          start_loading();
          m.route.set("/play");
        }
      })
      .catch(function (err) {
        console.log("Start error");
        console.log(err);
        set_error("StartGameError");
        start_loading();
        m.route.set("/play");
      });
  };

  var next_move = function (evt) {
    const dimension = Number(game.dimension);
    const idx = parseInt(evt.target.id);
    const row = Math.floor(idx / dimension);
    const col = idx % dimension;
    play_put_sound();
    console.log(toJSON(player_color) + " move " + row + ", " + col);
    const piece = "white" in player_color ? "O" : "*";
    var board = boards[boards.length - 1].board;
    if (
      same_color(player_color, next_color) &&
      valid_move(dimension, board, piece, row, col)
    ) {
      last_move_length += 1;
      board = Array.from(board);
      set_and_flip(dimension, board, piece, row, col);
      boards.push({ row: row, col: col, board: board });
      next_color = opponent_color(player_color);
      reversi
        .move(row, col)
        .then(function (res) {
          if ("OK" in res || "Pass" in res || "GameOver" in res) {
          } else {
            console.log("Unhandled game error, should not have happened!");
            console.log(toJSON(res));
          }
        })
        .catch(function (err) {
          console.log("Move error, ignore");
          console.log(err);
        });
    }
    m.redraw();
  };
  return {
    oninit: start_loading,
    onremove: function (vnode) {
      clearTimeout(refreshTimeout);
    },
    view: function (vnode) {
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
          expiring ? "Game will expire if no one moves!" : "",
          player_color,
          next_color,
          game,
          boards,
          next_move,
          function (e) {
            start_loading();
            m.route.set("/play");
          }
        );
      }
      return m("div", content);
    },
  };
}

function make_player_list(players, ordered) {
  let half = players.slice(0, 4);
  let more = players.slice(4, 8);
  let l = ordered ? "ol" : "ul";
  let make_player_link = function (player) {
    return m(
      "li",
      m(m.route.Link, { href: "/play?opponent=" + player.name }, [
        player.name + "(",
        m("span.player-score", Number(player.score)),
        ")",
      ])
    );
  };

  let list = [m("div.left-list", m(l, half.map(make_player_link)))];
  if (more.length > 0) {
    list.push(
      m(
        "div.right-list",
        m(l, { start: half.length + 1 }, more.map(make_player_link))
      )
    );
  }
  return list;
}

// these are global because we want to come back to /play remembering previous settings.
var inited = null;
var player_name = null;
var player_score = null;

function set_player_info(info) {
  player_name = info["name"];
  player_score = Number(info["score"]);
}

function Tips() {
  let next = 0;
  let tips = [
    [
      m("h4", "How to play:"),
      m("ul", [
        m("li", "1st player joining a game plays black."),
        m("li", "2nd player joining a game plays white."),
        m("li", "No password required, login is per-browser."),
      ]),
    ],
    [
      m("h4", "To invite a friend:"),
      m("ol", [
        m("li", ["Enter both of your names and click ", m("i", "Play!")]),
        m("li", "Once you are in game, share the URL with your friend."),
      ]),
    ],
    [
      m("h4", "How to score:"),
      m("ol", [
        m("li", "Get points by winning a game."),
        m("li", "Get more by beating higher-score players!"),
      ]),
    ],
    [
      m("h4", "To invite anyone:"),
      m("ol", [
        m("li", ["Leave the opponent name empty and click ", m("i", "Play!")]),
        m("li", "Once you are in game, share the URL with anyone."),
      ]),
    ],
  ];
  var games = [];
  var charts = [];

  let refresh_list = function () {
    reversi
      .list()
      .then(function (res) {
        // console.log("refresh_list");
        // console.log(res);
        if (res.player.length > 0) {
          set_player_info(res.player[0]);
        }
        games = [];
        function render_name(player, color) {
          return player.PlayerName
            ? [m("span." + color + "-name", player.PlayerName)]
            : [
                m("span." + color + "-name", player.Player[1].name),
                "(",
                m("span.player-score", player.Player[1].score),
                ")",
              ];
        }
        function render_play(player, content) {
          return m(
            m.route.Link,
            {
              href:
                "/game/" +
                player_name +
                "/." +
                (player.PlayerName ? player.PlayerName : player.Player[1].name),
            },
            content
          );
        }
        for (var i = 0; i < res.games.length; i++) {
          let game = res.games[i];
          if (!game.expiring && player_name && game.result.length == 0) {
            if (
              game.black.Player &&
              game.black.Player[0].toHex() == player_id
            ) {
              games.push(
                m("div", [
                  render_play(game.white, [
                    m("span.black-name", "You"),
                    " are playing against ",
                    ...render_name(game.white, "white"),
                    ", rejoin?",
                  ]),
                ])
              );
            } else if (
              game.white.Player &&
              game.white.Player[0].toHex() == player_id
            ) {
              games.push(
                m("div", [
                  render_play(game.black, [
                    m("span.white-name", "You"),
                    " are playing against ",
                    ...render_name(game.black, "black"),
                    ", rejoin?",
                  ]),
                ])
              );
            } else if (player_name.equalIgnoreCase(game.black.PlayerName)) {
              games.push(
                m("div", [
                  render_play(game.white, [
                    ...render_name(game.white, "white"),
                    " invites you to play, join?",
                  ]),
                ])
              );
            } else if (player_name.equalIgnoreCase(game.white.PlayerName)) {
              games.push(
                m("div", [
                  render_play(game.black, [
                    ...render_name(game.black, "black"),
                    " invites you to play, join?",
                  ]),
                ])
              );
            }
          }
        }
        // console.log(games);
        let top_players = res.top;
        let recent_players = res.recent;
        let available_players = res.available;
        charts = [];
        if (top_players.length > 0) {
          charts.push([
            m("h4", "Top players"),
            make_player_list(top_players, true),
          ]);
        }
        if (recent_players.length > 0) {
          charts.push([
            m("h4", "Recently played"),
            make_player_list(recent_players, false),
          ]);
        }
        // Available players is inaccurate before canister has access to time

        if (false && available_players.length > 0) {
          charts.push([
            m("h4", "Available players"),
            make_player_list(available_players, false),
          ]);
        }
      })
      .catch(function (err) {
        console.log("Refresh list error, ignore");
        console.log(err);
      });
  };

  return {
    onbeforeremove: function (vnode) {
      vnode.dom.classList.add("exit");
      refresh_list();
      next += 1;
      return new Promise(function (resolve) {
        vnode.dom.addEventListener("animationend", resolve);
      });
    },
    view: function () {
      let tip;
      let chart;
      if (games.length > 0) {
        return m(".fancy", m("div.tip", games));
      } else {
        if (charts.length == 0) {
          tip = tips[next % tips.length];
        } else {
          tip = tips[(next >> 1) % tips.length];
          chart = charts[(next >> 1) % charts.length];
        }
        return m(".fancy", m("div.tip", next % 2 == 0 ? tip : chart));
      }
    },
  };
}

// Play screen UI component.
function Play() {
  var tips_on = false;
  var opponent_name = null;
  var set_tips_on = function () {
    tips_on = true;
    m.redraw();
    clearTimeout(refreshTimeout);
    refreshTimeout = setTimeout(set_tips_off, 6000);
  };
  var set_tips_off = function () {
    tips_on = false;
    m.redraw();
    clearTimeout(refreshTimeout);
    refreshTimeout = setTimeout(set_tips_on, 1000);
  };

  var init_play = async function () {
    if (!inited) {
      if (process.env.NODE_ENV !== "production") {
        await agent.fetchRootKey();
      }
    }
    if (refreshTimeout) {
      clearTimeout(refreshTimeout);
    }
    set_tips_off();
    if (inited) {
      stop_loading();
      return;
    }
    reversi
      .register("")
      .then(function (res) {
        inited = true;
        console.log("Registered: " + toJSON(res));
        if ("ok" in res) {
          set_player_info(res["ok"]);
        }
        stop_loading();
        m.redraw();
      })
      .catch(function (err) {
        console.log("Register error");
        console.log(err);
        set_error("RegisterError");
        start_loading();
        m.route.set("/play");
      });
  };
  var play = function (e) {
    e.preventDefault();
    if (player_name == null || player_name == "") {
      set_error("InvalidName");
      return;
    }
    // clear error code on submit
    clear_error();
    console.log("Play " + player_name + " against " + opponent_name);
    start_loading();
    reversi
      .register(player_name)
      .then(function (res) {
        if ("ok" in res) {
          set_player_info(res["ok"]);
          m.route.set("/game/:player/:against", {
            player: player_name.trim(),
            against: "." + (opponent_name ? opponent_name.trim() : ""),
          });
        } else {
          let error_code = Object.keys(res["err"])[0];
          set_error(
            error_code,
            error_code == "NameAlreadyExists" ? player_name : null
          );
          m.route.set("/play");
        }
      })
      .catch(function (err) {
        console.log("Register error");
        console.log(err);
        set_error("RegisterError");
        m.route.set("/play");
      });
  };
  let tips = Tips();
  return {
    oninit: init_play,
    onremove: function (vnode) {
      clearTimeout(refreshTimeout);
    },
    view: function (vnode) {
      if (vnode.attrs.player && player_name == null) {
        player_name = vnode.attrs.player;
        vnode.attrs.player = null;
      }
      if (vnode.attrs.opponent) {
        opponent_name = vnode.attrs.opponent;
        vnode.attrs.opponent = null;
      }
      if (inited) {
        var title = "Welcome to Reversi!";
        var score = m("h2");
        var form = [];

        if (player_score === null) {
          form.push(
            m("input.input[type=text][placeholder=Your name]", {
              oninput: function (e) {
                player_name = e.target.value;
              },
              value: player_name,
            })
          );
        } else {
          title = [
            "Welcome back to Reversi, ",
            m("span.player-name", player_name),
            "!",
          ];
          score = m("h2", [
            m("span", "Your Score: "),
            m("span.player-score", player_score),
          ]);
        }
        form.push(m("label.label", "Choose an opponent"));
        form.push(
          m("input.input[placeholder=Opponent name]", {
            oninput: function (e) {
              opponent_name = e.target.value;
            },
            value: opponent_name,
          })
        );
        form.push(m("button.button[type=submit]", "Play!"));
        return [
          m("div.top-centered", [
            m("h1", title),
            m("img.logo", { src: logo }),
            score,
            m("div.error", get_error_message()),
            m("div", m("form", { onsubmit: play }, form)),
          ]),
          m("div.bottom-centered", m("div.tips", tips_on ? m(tips) : null)),
          m(
            "div.bottom",
            m(
              "a",
              { href: "https://github.com/ninegua/reversi" },
              "Source Code"
            )
          ),
        ];
      }
    },
  };
}

m.route(main, "/play", {
  "/play": Play,
  "/game/:player/:against": Game,
});

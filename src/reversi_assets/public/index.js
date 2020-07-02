import reversi from 'ic:canisters/reversi';
import './style.css';

var clientSize = Math.min(
      document.documentElement.clientWidth, 
      document.documentElement.clientHeight
    ) * .75;

function Board(dimension, board, onClick) {
  var cellSize = Math.floor(clientSize / dimension);
  var elems = [];
  elems.push(m("defs", [
    m("filter", { id: "shadow" }, [
      m("feDropShadow", { dx: 2, dy: 4, stdDeviation: 0.5 })
  ])]));
  for (var row = 0; row < dimension; row++) {
    for (var col = 0; col < dimension; col++) {
      // we accout for the \n in board string by + 1
      var idx = row * (dimension + 1) + col;
      var value = board.charAt(idx);

      elems.push(m("rect", {
        x: col * cellSize,
        y: row * cellSize,
        width: cellSize,
        height: cellSize,
        style: {
          fill: '#060',
          stroke: '#000',
          strokeWidth: 1,
        },
        id: row + "," + col,
        onclick: onClick,
      }));

      if (value != '.') {
        var pieceColor = value == 'O' ? '#fff' : '#000';
        var strokeColor = value == 'O' ? '#010' : '#fef';
        elems.push(m("circle", {
          cx: col * cellSize + cellSize * .50,
          cy: row * cellSize + cellSize * .50,
          r: cellSize * .45,
          strokeWidth: 2,
          stroke: strokeColor,
          "stroke-opacity": .4,
          fill: pieceColor,
          filter: "url(#shadow)",
        }))
      }
    }
  }
  return m("svg", {
      width: clientSize,
      height: clientSize,
    },  elems)
}

function Game() {
  var dimension = 0;
  var board = "";
  var color = 1;
  var get_board = function() {
    reversi.board().then((board_) => {
      board = board_;
      m.redraw();
    });
  };
  var init_game = function() {
    reversi.dimension().then((dimension_) => {
	  // dimension is a bigNumber object
      dimension = dimension_.toNumber();
      get_board();
    });
  };
  var next_move = function(evt) {
     var rowcol = evt.target.id.split(',');
     var row = parseInt(rowcol[0]);
     var col = parseInt(rowcol[1]);
     console.log(color + " move " + row + ", " + col)
     reversi.place(color, row, col).then((res) => {
       if (res == "OK") {
         color = 3 - color;
         get_board();
       }
     });
  };
  return {
    oninit: init_game,
    view: function(vnode) {
      return m("div", [
        m("h1", "Reversi"),
        Board(dimension, board, next_move),
        m("button", {onclick: get_board}, "board"),
      ]);
    },
  }
}

var m = require("mithril")
m.mount(document.body, Game)

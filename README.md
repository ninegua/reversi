# Multi-User Reversi / Othello Game on Internet Computer

This game runs on [Internet Computer] as a canister.
Users can communicate with this canister by sending messages, which are just asynchronous function calls.

The plan is to support multiple users and multiple games running concurrently, so users can choose to create new games or join existing ones.
But at the moment we only support one game, and two users have to take turns sharing the same browser window or terminal input.

## Canister API

`reset()` - Reset a game

`dimension() : Nat` - Get dimension of the board

`board() : Board` - Get the current state about the board in a text format.

`place(color, row, column) : Text` - Place a *White* (1) or *Black* (2) piece at the given coordinate

There are 4 possible responses:
 - `OK`: Piece placed
 - `PASS`: The given color cannot make any move and has to pass.
 - Game over
 - Invalid move

The canister will only accept a valid sequence of *Black/White* moves to reach the end of game.

## Frontend

A frontend is build with Javascript and [Mithril], and stored as a separate asset canister directly on [Internet Computer].
This allows users to access the game directly by entering a URL into a browser.

## Basic game flow

1. Once a game is started (with a `reset()` call), a player (*White*) is expected to make the first move (with `place()` call).
2. The another player (*Black*) is expected to make the next move (with `place()` call), and it continues.
3. If a player cannot make any move, the other player should take over.
4. When neither player can make next move, the game ends.
5. Whoever has the most pieces on the board when the game ends has won game.

## How to play (text version)

In one of the terminal window, start the `dfx` service:

```
cd examples/reversi
npm install
dfx start --background
dfx build
```

In another terminal window:

```
cd examples/reversi
sh run.sh
```

If everything works as expected, it will display something like this:

```
   1 2 3 4 5 6
  ------------
1  . . . . . .
2  . . . . . .
3  . . O * . .
4  . . * O . .
5  . . . . . .
6  . . . . . .
White 'O' move. (R)estart, (Q)uit, or Row,Col:
```

You may enter a valid coordinate for *White* (drawn as `O` on the board), e.g. "3,5" at the prompt to place a piece.
It will then display:

```
   1 2 3 4 5 6
  ------------
1  . . . . . .
2  . . . . . .
3  . . O O O .
4  . . * O . .
5  . . . . . .
6  . . . . . .
Black '*' move. (R)estart, (Q)uit, or Row,Col:
```

Now it is *Black*'s (drawn as `*` on the board) turn to place a piece.
The game will continue until no more pieces can be placed, by then it will declare game over, like this:

```
End Game! Whites = 5, Blacks = 31
   1 2 3 4 5 6
  ------------
1  * * * * * *
2  * * * * * *
3  * * * O * *
4  * * O * * *
5  * * * O O O
6  * * * * * *
```

Or this:

```
End Game! Whites = 20, Blacks = 1
   1 2 3 4 5 6
  ------------
1  . . O . . .
2  O . O O . .
3  O O O O O O
4  O O O O O O
5  O O O O . .
6  . . * . . .
```

[Mithril]: https://mithril.js.org/
[Internet Computer]: https://dfinity.org/

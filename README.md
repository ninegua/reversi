# Multiplayer Reversi Game on Internet Computer

**[Read about how the game was made!](https://ninegua.github.io/reversi)**

This game runs on [Internet Computer] as a canister.
Users can communicate with this canister by sending messages, which are just asynchronous function calls.

![Reversi Screenshots](./docs/screenshots.png)

## Backend

The game backend is written in [Motoko].

`register(player_name)` - Register the caller using the player name.

`start(opponent_name)` - Start a game expecting an opponent.
If the name is empty string, the game will accept whoever joins next.
The first player starting a game will play black, and the second player will play white.

`view()` - Get the up-to-date game state.

`move(row, col)` - Place a piece at the given row and column (caller must be a registered player and has started a game).

The game will also keep player scores across all games.

## Frontend

The GUI frontend is build with Javascript and [Mithril].
It is stored as a separate asset canister directly on [Internet Computer], and can be loaded at the game URL into a browser.

The terminal-based frontend no longer works with the new multiplayer API.
The [DFINITY SDK] currently lacks a way to switch or use different keypairs, which means the caller identity cannot change, so we don't have a way to run the game using the `dfx` command.

## Installation

To run the game locally, you need to install [DFINITY SDK] first, which also requires [Node.js] and `npm`.

After starting dfx (`dfx start --background`), run the following to build and install the canister:

```
make install
echo "http://localhost:8000/?canisterId=$(dfx canister id reversi_assets)"
```

The last command prints a URL, load it in a browser, and enjoy!

## License

All original code is released under MIT license.
The game UI also uses a free font [Akbar-Plain] made by Jon Bernhardt.

[DFINITY]: https://dfinity.org/
[DFINITY SDK]: https://sdk.dfinity.org/docs/
[Internet Computer]: https://dfinity.org/
[Motoko]: https://dfinity.org/
[Mithril]: https://mithril.js.org/
[Node.js]: https://nodejs.org/
[Akbar-Plain]: https://www.wobblymusic.com/groening/akbar.html

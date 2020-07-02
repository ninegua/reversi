import reversi from 'ic:canisters/reversi';

reversi.greet(window.prompt("Enter your name:")).then(greeting => {
  window.alert(greeting);
});

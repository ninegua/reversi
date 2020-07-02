#!/usr/bin/env bash
label=""
div=""

function init() {
  local res=$(dfx canister call reversi dimension 2>&1|sed -e 's/(//' -e 's/)//')
  [[ ! "$res" == ?(-)+([0-9]) ]] && echo $res > /dev/stderr && exit 1
  local i=1
  while [ $i -le $res ]; do
    label="$label $i"
    div="$div--"
    i=$((i+1))
  done
}

function restart() {
  dfx canister call 1 reset
  test "$?" != 0 && exit 1
}

function board() {
  local res=$(dfx canister call reversi board 2>&1)
  echo "$res" | grep -q error && echo $res && exit 1
  echo "  $label"
  echo "  $div"
  echo "$res"|sed -e 's/("//' -e 's/")//' -e 's/\\n/\n/g'|sed -e 's/\(.\)/\1 /g'|sed '/ /!d;='|sed 'N;s/\n/  /'
}

function color_name() {
  case "$1" in
    1)
            echo "White 'O'";;
    2)
            echo "Black '*'";;
    esac
}

function move() {
  local color=$1
  local col=$2
  local row=$3
  local res=$(dfx canister call reversi place "($color, $row, $col)" |sed -e 's/("//' -e 's/")//')
  echo $res > /dev/stderr
  case "$res" in
    OK)
      echo $((3 - $color));;
     *)
      echo $color;;
  esac
}

# install the canister
res=$(dfx canister install reversi 2>&1)
if [ "$?" != 0 ]; then
  # Skip error code 303 (which means canister already installed)
  echo $res | grep -q IC0307
  test "$?" != 0 && echo $res && exit 1
fi

# Get game board dimension
init

color=1

while true; do
  board
  name=$(color_name $color)
  read -p "$name move. (R)estart, (Q)uit, or Col,Row: " M
  case "$M" in
    Q)
      exit;;
    R)
      restart;;
    *)
      col=$(echo $M|sed -e 's/,.*//')
      row=$(echo $M|sed -e 's/^.*, *//')
      test "$row" -ge 1 -a "$row" -le 8 -a "$col" -ge 1 -a "$col" -le 8 2> /dev/null
      pass=$?
      if [ "$pass" = 0 ]; then
        col=$(($col - 1))
        row=$(($row - 1))
        color=$(move $color $col $row)
      else
        echo "Wrong input!"
      fi
      continue;;
  esac
done

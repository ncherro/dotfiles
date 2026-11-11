# --- Document scanning ---
# Turn photos of paper (HEIC/JPG/PNG/TIFF) into a clean black & white PDF.
#
#   bw-pdf ~/Downloads/some-dir      # every image in the dir -> some-dir.pdf
#   bw-pdf page1.HEIC page2.HEIC     # explicit files, in the order given
#   bw-pdf -g ~/Downloads/some-dir   # grayscale instead of pure black & white
#   bw-pdf -t 50 ~/Downloads/scans   # lower threshold = thicker/darker strokes
#   bw-pdf -r 300 ~/Downloads/scans  # coarser/smaller; default is 600 for B&W
#
# Output resolution matters a lot for the B&W mode: the page is thresholded
# AFTER resizing, so rendering at 600dpi keeps glyph edges smooth instead of
# quantizing them twice. Group4 compresses solid areas almost for free, so
# 600dpi B&W costs little (~370K for 4 pages vs ~190K at 300dpi). Grayscale is
# JPEG and scales far worse (10M at 600dpi), hence the lower default there.
#
# How it works: the paper background is estimated with a local MAXIMUM filter
# (not a blur) and divided out. That flattens uneven lighting and shadows while
# leaving large solid-black areas intact -- a blur-based estimate reads a black
# bar as "background" and inverts its interior to white. Because lighting is
# already flattened, a plain global threshold beats an adaptive one (-lat would
# likewise hollow out solid blacks, since each pixel there sits at its own local
# mean).
bw-pdf() {
  emulate -L zsh
  setopt local_options extended_glob no_nomatch

  local gray=0 thresh=55 out="" dpi=""
  while [[ "$1" == -* ]]; do
    case "$1" in
      -g|--gray)       gray=1; shift ;;
      -t|--threshold)  thresh="${2%\%}"; shift 2 ;;
      -r|--dpi)        dpi="$2"; shift 2 ;;
      -o|--output)     out="$2"; shift 2 ;;
      -h|--help)
        print "usage: bw-pdf [-g|--gray] [-t PCT] [-r DPI] [-o OUT.pdf] <dir | image...>"
        return 0 ;;
      *) print -u2 "bw-pdf: unknown option: $1"; return 2 ;;
    esac
  done

  # B&W is Group4, where resolution is cheap; grayscale is JPEG, where it isn't.
  [[ -n "$dpi" ]] || dpi=$(( gray ? 300 : 600 ))
  [[ "$dpi" == <-> ]] || { print -u2 "bw-pdf: --dpi must be a number"; return 2 }
  local pw=$(( 85 * dpi / 10 )) ph=$(( 11 * dpi ))

  (( $+commands[magick] )) || {
    print -u2 "bw-pdf: needs imagemagick -- brew install imagemagick"
    return 1
  }
  (( $# )) || { print -u2 "bw-pdf: no input given"; return 2 }

  local -a imgs
  if [[ $# -eq 1 && -d "$1" ]]; then
    local dir="${1:A}"
    imgs=( "$dir"/(#i)*.(heic|jpg|jpeg|png|tif|tiff)(N.on) )
    [[ -n "$out" ]] || out="$dir/${dir:t}.pdf"
  else
    imgs=( "$@" )
    [[ -n "$out" ]] || out="${1:A:h}/scan.pdf"
  fi
  (( ${#imgs} )) || { print -u2 "bw-pdf: no images found"; return 1 }

  local tmp; tmp="$(mktemp -d)" || return 1
  local -a pages
  local f p W H n=0

  for f in "${imgs[@]}"; do
    (( n++ ))
    read W H <<< "$(magick "$f" -auto-orient -format '%w %h' info:)" || {
      print -u2 "bw-pdf: cannot read $f"; rm -rf "$tmp"; return 1
    }
    p="$tmp/$(printf '%04d' $n).png"
    # NOTE: -compose is a *persistent* setting, so it must be reset to Over
    # after the divide -- otherwise -extent pads the canvas using Divide_Src
    # and every solid black area comes out as a hollow outline.
    magick "$f" -auto-orient -colorspace Gray \
      '(' +clone -resize 500x -statistic maximum 25x25 -blur 0x8 \
          -resize "${W}x${H}"'!' ')' \
      -compose Divide_Src -composite -compose Over \
      -normalize -level 30%,85% \
      -resize ${pw}x${ph} -background white -gravity center -extent ${pw}x${ph} \
      -density $dpi -units PixelsPerInch "$p" || {
        print -u2 "bw-pdf: failed on $f"; rm -rf "$tmp"; return 1
      }
    pages+=( "$p" )
    print -u2 "  [$n/${#imgs}] ${f:t}"
  done

  if (( gray )); then
    magick "${pages[@]}" -density $dpi -units PixelsPerInch \
      -compress JPEG -quality 88 "$out"
  else
    magick "${pages[@]}" -threshold "${thresh}%" \
      -density $dpi -units PixelsPerInch -compress Group4 "$out"
  fi
  local rc=$?
  rm -rf "$tmp"
  (( rc == 0 )) || { print -u2 "bw-pdf: failed writing $out"; return $rc }

  print "bw-pdf: wrote $out (${#pages} pages, ${dpi}dpi, $(du -h "$out" | cut -f1))"
}

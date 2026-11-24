// The flock's sheep, drawn with a few rounded shapes (styles in app.css). Shared by the main page and the floating companion.

export function sheep(motion = 'still', coat = 0) {
  return '<span class="sheep" data-motion="' + motion + '" data-coat="' + coat + '" aria-hidden="true"><i class="sheep-shadow"></i>'
    + '<span class="sheep-animal"><i class="sheep-tail"></i><i class="sheep-feet"></i><i class="sheep-fleece"></i>'
    + '<span class="sheep-head"><i class="sheep-ear"></i><i class="sheep-eye"></i><i class="sheep-cheek"></i></span></span><i class="sheep-note"></i></span>';
}

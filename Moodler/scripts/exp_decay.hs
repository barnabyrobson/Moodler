do
    plane <- currentPlane
    (x, y) <- fmap (quantise2 quantum) mouse
    panel <- container' "panel_3x1.png" (x, y) (Inside plane)
    lab <- label' "exp_decay" (x-25.0, y+75.0) (Inside plane)
    parent panel lab
    name <- new' "exp_decay"
    inp <- plugin' (name ++ ".decay_time") (x-21, y+25) (Inside plane)
    setColour inp "#control"
    parent panel inp
    inp <- plugin' (name ++ ".trigger") (x-21, y-25) (Inside plane)
    setColour inp "#control"
    parent panel inp
    out <- plugout' (name ++  ".result") (x+20, y) (Inside plane)
    setColour out "#control"
    parent panel out
    recompile
    return ()

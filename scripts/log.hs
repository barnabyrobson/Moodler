do
    plane <- currentPlane
    (x, y) <- mouse
    panel <- container' "panel_3x1.bmp" (x, y) plane
    lab <- label' "log" (x-25.0, y+75.0) plane
    parent panel lab
    name <- new' "log"
    -- in
    inp <- plugin' (name ++ ".signal") (x-21, y) plane
    parent panel inp
    -- out
    out <- plugout' (name ++  ".result") (x+20, y) plane
    parent panel out
    recompile
    return ()

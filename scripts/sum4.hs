do
    plane <- currentPlane
    (x, y) <- mouse
    panel <- container' "panel_4x1.bmp" (x, y) plane
    lab <- label' "sum4" (x-25.0, y+75.0) plane
    parent panel lab
    name <- new' "sum4"
    -- in
    inp <- plugin' (name ++ ".signal1") (x-21, y+75) plane
    parent panel inp
    -- in
    inp <- plugin' (name ++ ".signal2") (x-21, y+25) plane
    parent panel inp
    -- in
    inp <- plugin' (name ++ ".signal3") (x-21, y-25) plane
    parent panel inp
    -- in
    inp <- plugin' (name ++ ".signal4") (x-21, y-75) plane
    parent panel inp
    -- out
    out <- plugout' (name ++  ".result") (x+20, y) plane
    parent panel out
    recompile
    return ()

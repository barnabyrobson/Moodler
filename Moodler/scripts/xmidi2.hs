
do
    (x0, y0) <- mouse
    let (x, y) = quantise2 quantum (x0, y0)
    root <- currentPlane

    keyboard2 <- new' "input"
    alias "keyboard2" keyboard2

    trigger2 <- new' "input"
    alias "trigger2" trigger2

    modulation2 <- new' "input"
    alias "modulation2" modulation2

    bend2 <- new' "input"
    alias "bend2" bend2

    container0 <- container' "panel_xkeyboard2.png" (x+456-456.0,y-36+36.0) (Inside root)
    out1 <- plugout' (keyboard2 ! "result") (x+456-396.0,y-36+60.0+48) (Outside container0)
    setColour out1 "#control"
    out2 <- plugout' (trigger2 ! "result") (x+456-396.0,y-36+12.0+48) (Outside container0)
    setColour out2 "#control"
    out3 <- plugout' (modulation2 ! "result") (x+456-396.0,y-36+12.0) (Outside container0)
    setColour out3 "#control"
    out4 <- plugout' (bend2 ! "result") (x+456-396.0,y-36+12.0-48) (Outside container0)
    setColour out4 "#control"

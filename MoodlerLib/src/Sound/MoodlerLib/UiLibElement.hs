module Sound.MoodlerLib.UiLibElement where

data KnobStyle = KnobStyle | SliderStyle deriving (Eq, Show)

data ElementType = ContainerType
                 | InType
                 | OutType
                 | KnobType
                 | LabelType
                 | ProxyType
                 | ImageType
                 | SelectorType deriving (Eq, Show)
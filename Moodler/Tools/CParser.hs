import qualified Data.ByteString.Char8 as B
import Language.C.Data.Position
import Language.C.Data.Name
import Language.C.Parser

main :: IO ()
main = do
    code <- B.getContents
    case execParser translUnitP code (position 0 "" 0 0) builtinTypeNames newNameSupply of
        Right parsed -> print parsed
        Left e -> print e

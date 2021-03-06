{-|
Module      : CodeGen
Description : C code generation
Maintainer  : dpiponi@gmail.com

Generate C code from a Moodler graph.
This code is painfully verbose.
It really needs quasiquoting but I believe the existing C quasiquoter
uses a different AST representation and doesn't support operators like
sizeof and __attribute__.
-}

{-# LANGUAGE FlexibleContexts #-}

module CodeGen(gen) where

import Control.Lens hiding (set)
import Control.Monad.State
import Control.Monad.Writer
import Data.Function
import Data.List
import Data.Maybe
import Language.C.Data.Node
import Language.C.Pretty
import Language.C.Syntax.AST
import Text.PrettyPrint
import qualified Data.Map as M

import CGen
import CLens
import Module
import MoodlerSymbols
import Parser
import Synth
import TopologicalSort
import Utils

-- | There are three types of variable associated with an exec() function
-- that Moodler cares about:
-- inputs, outputs and internal state variables
-- The function 'varsFromNodeType' builds a structure with their names.
-- XXX This isnt full story. InName... XXX
varsFromNodeType :: NodeType -> M.Map InName CExpr -> Vars
varsFromNodeType NodeType { _stateNames = states
                          , _inNames = ins
                          , _outNames = outs } = Vars states outs ins

execBody :: NodeType -> M.Map InName CExpr -> CStat
execBody nodeType@NodeType { _execCode = e
                           , _nodeTypeName = typeName } connections =
    let variables = varsFromNodeType nodeType connections 
    in rewriteVars2 typeName variables e

-- Inlined in exec()
execInlined :: ModuleName -> NodeType -> M.Map InName CExpr -> [CStat]
execInlined nodeName nodeType connections =
    let e = _execCode nodeType
    in if not (isStatementEmpty (e ^. funDefStat))
        then let variables = varsFromNodeType nodeType connections 
                 e' = rewriteVars (_getModuleName nodeName) variables e
             in fromMaybe [e'] (justStmts e')
    else []

-- | Generate call to exec() member of MSL module.
-- These calls are only made if the exec() function is not labelled
-- as inline.
execCall :: ModuleName          -- ^ The name of this module
            -> NodeType         -- ^ The modules type as specified by the MSL code
            -> ModuleTypeName   -- ^ The name of the module, ie. the name of the MSL file
            -> [InName]         -- ^ TODO
            -> M.Map InName Out -- ^ TODO
            -> CStat            -- ^ The C statement calling the exec() function
execCall nodeName nodeType typeName inputNames connections =
    cExpr $ cCall (cVar (cIdent (_getModuleTypeName typeName ++ "_exec")))
                  (map (\inputName ->
                            let x = fromMaybe Disconnected (M.lookup inputName connections)
                            in cExprForOut (nodeType ^. inNames) inputName x 
                        ) inputNames ++
                   [cAddr (cVar (cIdent "state") `cArrow` cIdent (_getModuleName nodeName))])

genIncludes :: MonadWriter String m =>
               [String] -> m ()
genIncludes includes = forM_ includes $ \include ->
    tell $ "#include <" ++ include ++ ">\n"

genIncludes' :: MonadWriter String m =>
                String -> [String] -> m ()
genIncludes' libDirectory includes = forM_ includes $ \include ->
    tell $ "#include \"" ++ libDirectory ++ "/" ++ include ++ "\"\n"

genHeaders :: MonadWriter String m => String -> [String] -> m ()
genHeaders libDirectory includeList = do
    genIncludes ["stdio.h", "stdlib.h", "stddef.h", "string.h", "math.h", "complex.h"]
    genIncludes' libDirectory ("moodler_lib.h" : includeList)

-- Generate elements of struct corresponding to one primitive module.
genNodeStruct :: NodeType -> CExtDecl
genNodeStruct NodeType { _nodeTypeName = name
                       , _stateDecls = decls } =
    let stateStruct1 = structType (cIdent (_getModuleTypeName name))
                                  (Just decls)
    in CDeclExt $ CDecl [CTypeSpec stateStruct1] [(Nothing, Nothing, Nothing)] undefNode

definePrimitiveStruct :: ModuleName -> ModuleTypeName -> CDecl
definePrimitiveStruct nodeName primTypeName =
    let stateType2 = structType (cIdent (_getModuleTypeName primTypeName)) Nothing
    in CDecl [CTypeSpec stateType2]
             [(Just (CDeclr (Just (cIdent (_getModuleName nodeName))) [] Nothing [] undefNode), Nothing, Nothing)]
             undefNode

genStateStruct :: [Module] -> CExtDecl
genStateStruct moduleList =
    let members2 = flip map moduleList $ \node -> 
                let name = _getNodeName node
                in definePrimitiveStruct name (_nodeTypeName (_getNodeType node))
    in CDeclExt $ CDecl [CTypeSpec (structType (cIdent "State") (Just members2))] [] undefNode

genShaderFunctions :: NodeType -> CExtDecl
genShaderFunctions nodeType@NodeType { _execCode = execFunDef
                                     , _nodeTypeName = typeName } =
    let codeBody = execBody nodeType undefined
        typeString = _getModuleTypeName typeName
    in CFDefExt $ execFunDef & funDefDeclr %~ rewriteShaderDeclr (typeString ++ "_exec")
                                                                 typeString typeString
                             & funDefStat .~ codeBody

cExprForOut :: M.Map InName CDecl -> InName -> Out -> CExpr
cExprForOut inDecls inName Disconnected =
    fromMaybe (intConst 0) $ inDecls ^? ix inName . to getNormalFromCDecl . each

cExprForOut _ _ (Out name' name'') =
        cVar (cIdent "state") `cArrow` cIdent (_getModuleName name')
                              `cDot` cIdent (_getOutName name'')

-- | The type of the "exec" C function.
executeType :: CDerivedDeclr
executeType =
    CFunDeclr (Right (
              [
                  cPtrTo (structType (cIdent "State") Nothing) (cIdent "state"),
                  cPtrTo (CDoubleType undefNode) (cIdent "buffer")
              ], False))
              [] undefNode

executeFunction :: CStatement NodeInfo -> CFunctionDef NodeInfo
executeFunction stmt = 
    CFunDef [CTypeSpec (CVoidType undefNode)]
            (CDeclr (Just (cIdent "execute"))
                    [executeType]
                    Nothing [] undefNode)
            [] (CCompound [] [CBlockStmt stmt] undefNode) undefNode

-- | Builds main audio generating loop.
mainLoop :: CStat    -- ^ The body of the loop.
            -> CStat -- ^ The full loop of the form
                     -- ^ @
                     -- ^ for (i = 0; i < 256; ++i) {
                     -- ^     <body>
                     -- ^ }
                     -- ^ @
mainLoop stat = 
    let iIdent = cIdent "i"
        iVar = cVar iIdent
    in CFor (Right (CDecl [CTypeSpec (CIntType undefNode)]
                                  [(Just (CDeclr (Just iIdent) [] Nothing [] undefNode),
                                    Just (CInitExpr (intConst 0) undefNode),
                                    Nothing)]
                                  undefNode))
            (Just (iVar `cLe` intConst 256))
            (Just (cPreInc iVar))
            stat
            undefNode

genExec :: [Module] -> CExtDecl
genExec sortedPrimitives =
    let compoundParts =
            flip map sortedPrimitives $ \node ->
                let name = _getNodeName node
                    nodeType@NodeType { _inList = inputNames
                                      , _nodeTypeName = typeName
                                      } = _getNodeType node
                    connections = _inputNodes node
                    connections' = M.mapWithKey (cExprForOut (nodeType ^. inNames))
                                                connections
                in if _getModuleName name == "out" || _isInlined nodeType
                    then execInlined name nodeType connections'
                    else [execCall name nodeType typeName
                                   inputNames connections]
        compoundStatement = CCompound []
                                      (map CBlockStmt (concat compoundParts))
                                      undefNode

        loop = mainLoop compoundStatement
    in CFDefExt $ executeFunction loop
    
structName :: String -> CDecl
structName n = CDecl [CTypeSpec (structType (cIdent n) Nothing)] [] undefNode

genNodeAddressTable :: NodeType -> CExtDecl
genNodeAddressTable nodeType =
    let stateVars = _stateNames nodeType
        name = _nodeTypeName nodeType
        name' = _getModuleTypeName name
        stmts = flip map stateVars $ \varName ->
                    (varName, cOffsetOf (structName name') (cIdent varName))
    in makeNodeTable "NodeRecord" (name' ++ "_address_table") stmts

addressTable :: [Module] -> CExtDecl
addressTable modules =
    let stmts = map f modules :: [(String, CExpr, CExpr, CExpr)]
        f node = (_getModuleName (_getNodeName node),
                  cV (_getModuleTypeName (_nodeTypeName (_getNodeType node)) ++ "_address_table"),
                  cOffsetOf structState (cIdent (_getModuleName (_getNodeName node))),
                  cAddr (cV (_getModuleTypeName (_nodeTypeName (_getNodeType node)) ++ "_init"))
                  )
    in makeStateTable "StateRecord" "address_table" stmts

-- Create C function to return offset into state corresponding
-- to fields.
addressType :: CDerivedDeclr
addressType =
    CFunDeclr (Right (
              [
                  cConstPtrTo (CCharType undefNode) (cIdent "node"),
                  cConstPtrTo (CCharType undefNode) (cIdent "field")
              ], False))
              [] undefNode

structState :: CDecl
structState = CDecl [CTypeSpec (structType (cIdent "State") Nothing)]
                    [] undefNode

genAddress :: CExtDecl
genAddress =
    let stmt = cReturn (Just (cCall (cV "get_address") [cV "address_table", cV "node", cV "field" ]))
    in CFDefExt $ CFunDef [CTypeSpec (CIntType undefNode)]
                            (CDeclr (Just (cIdent "address"))
                                    [addressType]
                                    Nothing [] undefNode)
                            [] (cCompound [] [stmt]) undefNode

init2HelperType :: String -> CDerivedDeclr
init2HelperType name =
    CFunDeclr (Right (
              [
                  cPtrTo (CVoidType undefNode) (cIdent (name ++ "0"))
              ], False))
              [] undefNode

instantiateInitHelper :: ModuleTypeName -> NodeType -> CStat
instantiateInitHelper nodeName nodeType =
    let i = _initCode nodeType
        variables = varsFromNodeType nodeType M.empty
    in rewriteInitVars (_getModuleTypeName nodeName) variables i

genInitialisers :: NodeType -> CExtDecl
genInitialisers node =
      let initSource = instantiateInitHelper (_nodeTypeName node) node
          typeName = _getModuleTypeName (_nodeTypeName node)

      in CFDefExt $ CFunDef [CTypeSpec (CVoidType undefNode)]
                      (CDeclr (Just (cIdent (typeName ++ "_init")))
                              [init2HelperType typeName]
                              Nothing [] undefNode)
                      [] initSource undefNode

genInit :: Writer String ()
genInit = do
    tell "void init2(struct State *state, const char *node) {\n"
    tell "    init_node(state, address_table, node);\n"
    tell "}\n"

genSet :: Writer String ()
genSet = do
    tell "void set(struct State *state, const char *node,\n"
    tell "                  const char *field, double value) {\n"
    tell "    int offset = address(node, field);\n"
    tell "    *(double *)((char *)state+offset) = value;\n"
    tell "    printf(\"set %s.%s(%d)=%f\\n\",node,field,offset,value);\n"
    tell "}\n"

-- XXX No free for that strdup
genSetString :: Writer String ()
genSetString = do
    tell "void set_string(struct State *state, const char *node,\n"
    tell "                  const char *field, const char *value) {\n"
    tell "    int offset = address(node, field);\n"
    tell "    *(char **)((char *)state+offset) = strdup(value);\n"
    tell "    printf(\"set %s.%s(%d)=%s\\n\",node,field,offset,value);\n"
    tell "}\n"

--- XXX Allocating 1MB for state.
-- This needs to be managed at some point.
genCreate :: Writer String ()
genCreate = do
    tell "struct State *create() {\n"
    tell "struct State *x = malloc(1024*1024);\n"
    tell "return x;\n"
    tell "}\n"

sampleRate :: Double
sampleRate = 1.0/48000

makeNodeTable :: String -> String -> [(String, CExpr)] -> CExtDecl
makeNodeTable typeName name entries =
    let cEntry (k, v) = ([], CInitList [
                                        ([], CInitExpr (stringConst k) undefNode),
                                        ([], CInitExpr v undefNode)
                                      ] undefNode)
        zeroInit = ([], cInitExpr (intConst 0))
        cEntries = map cEntry entries ++ [([], CInitList [zeroInit, zeroInit] undefNode)]
    in CDeclExt (CDecl [CTypeSpec (
        structType (cIdent typeName) Nothing
    )] [(Just (CDeclr (Just (cIdent name)) [
            CArrDeclr [] (CNoArrSize False) undefNode] Nothing [] undefNode),
        Just (CInitList cEntries undefNode), Nothing)] undefNode)

makeStateTable :: String -> String -> [(String, CExpr, CExpr, CExpr)] -> CExtDecl
makeStateTable typeName name entries =
    let f e = ([], cInitExpr e)
        cEntry (k, v1, v2, v3) =
                ([], CInitList (map f [stringConst k, v1, v2, v3]) undefNode)
        zeroInit = ([], cInitExpr (intConst 0))
        cEntries = map cEntry entries ++
                        [([], CInitList (replicate 4 zeroInit) undefNode)]
    in CDeclExt (CDecl [CTypeSpec (structType (cIdent typeName) Nothing)]
                       [(Just (CDeclr (Just (cIdent name)) [
                            CArrDeclr [] (CNoArrSize False) undefNode]
                                      Nothing [] undefNode),
                        Just (CInitList cEntries undefNode), Nothing)]
                       undefNode)

-- | Generate entire C module from internal Moodler graph.
gen :: String                    -- ^ The directory container C header files.
       -> Synth                  -- ^ The entire synth to generate C code for.
       -> Module                 -- ^ The module representing the final output.
       -> Writer String [String] -- ^ Returns list of libraries for linking, writing C code.
                                 -- as side effect using 'Writer' monad.
gen currentDirectory synth out' = do

    let moduleList = sortBy (compare `on` _moduleNumber) $ M.elems synth
    let sortedPrimitives = topologicalSort synth out'

    let nodeTypes = map _getNodeType moduleList
    let uniqNodeTypes = uniqBy (compare `on` _nodeTypeName) nodeTypes
    let includeList = concatMap _nodeInclude uniqNodeTypes

    genHeaders currentDirectory includeList
    tell $ "const double dt = " ++ show sampleRate ++ ";\n"

    let linkList = concatMap _nodeLink uniqNodeTypes
    let inlineNodeTypes = filter (not . _isInlined) uniqNodeTypes

    let nodeStructs = map genNodeStruct uniqNodeTypes
    let stateStruct = genStateStruct moduleList
    let initialisers = map genInitialisers uniqNodeTypes
    let table = map genNodeAddressTable uniqNodeTypes
    let defs = map genShaderFunctions inlineNodeTypes
    let exec = genExec sortedPrimitives
    let address = genAddress

    let units = nodeStructs ++ [stateStruct] ++ initialisers ++ table
                            ++ defs ++ [addressTable moduleList]
                            ++ [address] ++ [exec]
    let sourceCode = CTranslUnit units undefNode

    tell (render (pretty sourceCode))
    tell "\n"

    genInit --moduleList
    genCreate
    genSet
    genSetString
    return linkList

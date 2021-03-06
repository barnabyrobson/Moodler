{-|
Module      : ContainerTree
Description : Deals with tree structure of a synth in UI.
Maintainer  : dpiponi@gmail.com

Maintains tree structure of a synth in UI. Ensures that when UI
elements are added, moved or deleted the appropriate links
are maintained. Also provides method for examining tree.
-}

{-# LANGUAGE FlexibleContexts #-}

module ContainerTree(inOrOutParent,
                     getAllContainerProxyDescendants,
                     getAllContainerDescendants,
                     getAllContainers,
                     getMinimalParents,
                     moveElementToPlane,
                     createdInsideParent,
                     createdInParent,
                     checkExists,
                     findContainer,
                     unparent,
                     deleteElement,
                     reparent) where

import Control.Monad.State
import Control.Lens hiding (inside, outside)
import qualified Data.Set as S
import qualified Data.Map as M
import qualified Data.List as L
import Control.Applicative

import Sound.MoodlerLib.Symbols

import World
import WorldSupport
import UIElement
import Utils
import Wiring
import ServerState
--import Control.Monad.Morph

-- | Check whether a 'UiId' does map to a real UI element.
checkExists :: (Functor m, MonadState World m) =>
               UiId      -- ^ The 'UiId' to check
               -> m Bool -- returns whether or not it exists
checkExists i = M.member i <$> use (serverState . uiElements)

-- | Ensures a UI element newly created inside a container is inserted into UI tree structure.
createdInsideParent :: MonadState World m =>
                   UiId         -- ^ The proposed new 'UiId' for the element
                   -> UIElement -- ^ The UI element itself
                   -> UiId      -- ^ The parent inside which it is created
                   -> m ()
createdInsideParent n e q = do
    serverState . uiElements %= M.insert n e
    assignElementToInside n q

-- | Ensures a UI element newly created outside a container is inserted into UI tree structure.
createdOutsideParent :: MonadState World m =>
                   UiId         -- ^ The proposed new 'UiId' for the element  
                   -> UIElement -- ^ The UI element itself                   
                   -> UiId      -- ^ The parent outside which it is created   
                   -> m ()
createdOutsideParent n e q = do
    serverState . uiElements %= M.insert n e
    assignElementToOutside n q

createdInParent :: MonadState World m =>
                   UiId -> UIElement -> Location -> m ()
createdInParent n e (Inside q) = createdInsideParent n e q
createdInParent n e (Outside q) = createdOutsideParent n e q

assignElementToInside :: MonadState World m => UiId -> UiId -> m ()
assignElementToInside e newPlane' = do
    serverState . uiElements . ix newPlane' . inside %= S.insert e
    serverState . uiElements . ix e . ur . UIElement.parent .= Inside newPlane'

assignElementToOutside :: MonadState World m => UiId -> UiId -> m ()
assignElementToOutside e newPlane' = do
    serverState . uiElements . ix newPlane' . outside %= S.insert e
    serverState . uiElements . ix e . ur . UIElement.parent .= Outside newPlane'

withContaining :: Monad m => UIElement -> (S.Set UiId -> m ()) -> m ()
withContaining elt f = 
    case elt of
        Container { _inside = insideCts, _outside = outsideCts } ->
            f (S.union insideCts outsideCts)
        _ -> return () -- XXX Come back to this. Be explicit.

deleteElement :: (Functor m, MonadIO m,
                 MonadState World m) => UiId -> m ()
deleteElement t = do
    removeAllCablesFrom t
    elt <- getElementById "deleteElement" t
    withContaining elt $ \ids -> mapM_ deleteElement (S.toList ids)
    removeFromParent t
    serverState . uiElements %= M.delete t
    currentSelection %= L.delete t

isContainer :: UIElement -> Bool
isContainer elt =
    case elt of
        Container {} -> True
        _ -> False

isContainerM :: UiId -> MoodlerM Bool
isContainerM i =
    isContainer <$> getElementById "isContainerM" i

getAllContainers :: MoodlerM [UiId]
getAllContainers =
    (M.keys . M.filter isContainer) <$> use (serverState . uiElements)

unparent :: MonadState World m => UiId -> m ()
unparent childId = do
    thisPlane <- use (planeInfo . planes)
    reparent (Inside thisPlane) childId

reparent :: MonadState World m => Location -> UiId -> m ()
reparent (Outside newParentId) childId = do
    removeFromParent childId
    serverState . uiElements . ix newParentId . outside %= S.insert childId
    serverState . uiElements . ix childId . ur . parent .= Outside newParentId
reparent (Inside newParentId) childId = do
    removeFromParent childId
    serverState . uiElements . ix newParentId . inside %= S.insert childId
    serverState . uiElements . ix childId . ur . parent .= Inside newParentId

inOrOutParent :: Location -> UiId
inOrOutParent (Inside i) = i
inOrOutParent (Outside o) = o

removeFromParent :: MonadState World m => UiId -> m ()
removeFromParent childId = do
    childElt <- getElementById "UISupport.hs" childId
    let currentParentId = inOrOutParent (_parent (_ur childElt))
    -- XXX Bit of a hack deleting from both
    serverState . uiElements . ix currentParentId . outside %= S.delete childId
    serverState . uiElements . ix currentParentId . inside %= S.delete childId

-- Includes argument in result
getDescendants :: MonadState World w =>
                  (UIElement -> [UiId]) -> UiId -> w [UiId]
getDescendants getChildren i = do
    e <- getElementById "UISupport.hs" i
    let f = getChildren e
    descendants <- mapM (getDescendants getChildren) f
    return (uniq (i : concat descendants))

getAllDescendants :: (Functor w, MonadState World w) =>
                     (UIElement -> [UiId]) -> [UiId] -> w [UiId]
getAllDescendants getChildren = fmap (uniq . concat) .
                                    mapM (getDescendants getChildren)

getContainerProxyChildren :: UIElement -> [UiId]
getContainerProxyChildren (Container { _inside = insideCts, _outside = outsideCts }) =
    S.toList insideCts ++ S.toList outsideCts
getContainerProxyChildren _ = []

getContainerChildren :: UIElement -> [UiId]
getContainerChildren (Container { _outside = cts }) = S.toList cts
getContainerChildren _ = []

getAllContainerProxyDescendants :: (Functor w,
                                   MonadState World w) =>
                                   [UiId] -> w [UiId]
getAllContainerProxyDescendants = getAllDescendants
                                    getContainerProxyChildren

getAllContainerDescendants :: (Functor w, MonadState World w) =>
                              [UiId] -> w [UiId]
getAllContainerDescendants = getAllDescendants getContainerChildren

moveElementToPlane :: MonadState World m => UiId -> Location -> m ()
moveElementToPlane = flip reparent

-- Find selements of second list whose parents are not in first.
-- Avoids selections containing both parents and their children.
getMinimalParents :: (Functor m, MonadState World m) =>
                     [UiId] -> [UiId] -> m [UiId]
getMinimalParents everything sel = do
    selElts <- getElementsById "getMinimalParents" sel
    return [item | (item, elt) <- zip sel selElts,
                   inOrOutParent (elt ^. ur . parent) `notElem` everything]

-- Find a container somewhere in a list of ids.
-- Assumes there is precisely one. XXX
findContainer :: [UiId] -> MoodlerM (Maybe (UiId, [UiId]))
findContainer es = do
    (a, b) <- partitionM isContainerM es
    case a of
        [a'] -> return $ Just (a', b)
        _ -> return Nothing

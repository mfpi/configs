-- current darcs as of 2010-12-31
{-# LANGUAGE
     DeriveDataTypeable,
     FlexibleContexts,
     FlexibleInstances,
     MultiParamTypeClasses,
     NoMonomorphismRestriction,
     PatternGuards,
     ScopedTypeVariables,
     TypeSynonymInstances,
     UndecidableInstances
     #-}
{-# OPTIONS_GHC -W -fwarn-unused-imports -fno-warn-missing-signatures #-}

import XMonad.Util.NamedScratchpad
import Control.Applicative
import Control.Monad
import Control.Monad.Instances ()
import Control.Monad.Writer
import Data.List
import Data.Maybe
import Data.Traversable(traverse)
import Graphics.X11.Xinerama
import qualified Data.Map as M
import qualified XMonad.StackSet as W
import qualified XMonad.Util.ExtensibleState as XS
import System.IO
import XMonad
import XMonad.Actions.DwmPromote
import XMonad.Actions.FloatSnap
import XMonad.Actions.GridSelect
import XMonad.Actions.Search
import XMonad.Actions.SpawnOn
import XMonad.Actions.Submap
import XMonad.Actions.TopicSpace
import XMonad.Actions.UpdatePointer
import XMonad.Actions.Warp
import XMonad.Hooks.DynamicLog
import XMonad.Hooks.EwmhDesktops
import XMonad.Hooks.ManageDocks
import XMonad.Hooks.ManageHelpers
import XMonad.Hooks.UrgencyHook
import XMonad.Layout.ResizableTile
import XMonad.Layout.Accordion
import XMonad.Layout.MultiToggle
import XMonad.Layout.Combo
import XMonad.Layout.BoringWindows
import XMonad.Layout.Drawer
import XMonad.Layout.Grid
import XMonad.Layout.TwoPane
import XMonad.Layout.IM
import XMonad.Layout.LayoutHints
import XMonad.Layout.LayoutModifier
import XMonad.Layout.Magnifier
import XMonad.Layout.Master
import XMonad.Layout.Mosaic
import XMonad.Layout.MosaicAlt
import XMonad.Layout.MouseResizableTile
import XMonad.Layout.Named
import XMonad.Layout.NoBorders
import XMonad.Layout.PerWorkspace
import XMonad.Layout.Simplest
import XMonad.Layout.SimplestFloat
import XMonad.Layout.SubLayouts
import XMonad.Layout.Tabbed
import XMonad.Layout.TrackFloating
import XMonad.Layout.WindowNavigation
import XMonad.Prompt
import XMonad.Prompt.RunOrRaise
import XMonad.Prompt.Ssh
import XMonad.Prompt.Window
import XMonad.Prompt.XMonad
import XMonad.Util.EZConfig
import XMonad.Util.Replace
import XMonad.Util.Run

scratchpads =
    [ NS "htop" "urxvt -e htop" (title =? "htop") defaultFloating
    , NS "workspace" "urxvt -name workspace" (title =? "workspace") defaultFloating
    ] where role = stringProperty "WM_WINDOW_ROLE"

main :: IO ()
main = do
    replace
    checkTopicConfig myTopics myTopicConfig
    let urgency
            | True = withUrgencyHook FocusHook
            | True = withUrgencyHook NoUrgencyHook
    xmonad . ewmh . urgency . myConfig
        =<< mapM xmobarScreen =<< getScreens

sofficeToolbox = className =? "OpenOffice.org 3.1"
                <&&> isInProperty "WM_PROTOCOLS" "WM_TAKE_FOCUS"

myConfig hs = let c = defaultConfig {
      layoutHook = myLayout
    , focusFollowsMouse = False
    , focusedBorderColor = "red"
    , startupHook = do
        return () -- supposedly to avoid inf. loops with checkKeymap
        checkKeymap (myConfig []) (myKeys c)
    , terminal = "urxvt -e zsh"
    , modMask = mod4Mask
    , logHook = do
        multiPP'
            (mergePPOutputs [XMonad.Actions.TopicSpace.pprWindowSet myTopicConfig,
                             dynamicLogString . onlyTitle])
            myPP
            myPP{ ppTitle = const "" }
            hs
        -- updatePointer (TowardsCentre 0.2 0.2)
    , handleEventHook = ewmhDesktopsEventHook <+> fullscreenEventHook <+> focusFollow <+>
                    (\e -> case e of
                        PropertyEvent{ ev_window = w } -> do
                            isURXVT <- runQuery (className =? "URxvt") w
                            if not isURXVT then hintsEventHook e else return (All True)
                        _ -> return (All True))
    , workspaces = myTopics
    , manageHook = mconcat
                    [manageSpawn
                    ,isFullscreen --> doFullFloat
                    -- ,className =? "MPlayer" --> doFullFloat
                    ,className =? "XTerm" --> queryMerge (className =? "XTerm")
                    ,manageDocks
                    , namedScratchpadManageHook scratchpads
                    ]
    } in additionalKeysP c (myKeys c)

myXPConfig :: XPConfig
myXPConfig = greenXPConfig { font = "xft:Profont:pixelsize=15:autohint=true" }

gsConfig = defaultGSConfig { gs_navigate = fix $ \self ->
    let navKeyMap = M.mapKeys ((,) 0) $ M.fromList $
                [(xK_Escape, cancel)
                ,(xK_Return, select)
                ,(xK_slash , substringSearch self)]
           ++
            map (\(k,a) -> (k,a >> self))
                [(xK_Left  , move (-1,0 ))
                ,(xK_h     , move (-1,0 ))
                ,(xK_n     , move (-1,0 ))
                ,(xK_Right , move (1,0  ))
                ,(xK_l     , move (1,0  ))
                ,(xK_i     , move (1,0  ))
                ,(xK_Down  , move (0,1  ))
                ,(xK_j     , move (0,1  ))
                ,(xK_e     , move (0,1  ))
                ,(xK_Up    , move (0,-1 ))
                ,(xK_u     , move (0,-1 ))
                ,(xK_y     , move (-1,-1))
                ,(xK_m     , move (1,-1 ))
                ,(xK_space , setPos (0,0))
                ]
    in makeXEventhandler $ shadowWithKeymap navKeyMap (const self) }

data ExpandEdges a = ExpandEdges Int deriving (Read,Show)

instance LayoutModifier ExpandEdges Window where
    modifyLayout (ExpandEdges n) ws (Rectangle x y w h) = let
            bigRect = Rectangle (x - fromIntegral n) (y - fromIntegral n)
                                (w + 2*fromIntegral n) (h + 2*fromIntegral n)
        in
        runLayout ws bigRect

-- | push edges off-screen
expandEdges n layout = ModifiedLayout (ExpandEdges n) layout



-------------------- Layout ----------------------------------
myLayout =
         trackFloating . smartBorders
         . avoidStruts
         . onWorkspace "xm-conf" ((nav $ ModifiedLayout (ExpandEdges 1) (Tall 1 0.3 0.5)) ||| Full)
         $ m ||| named "F" (noBorders Full) ||| (TwoPane (3/100) (1/2))
             ||| (named "Full|Acc" $ combineTwo myTiled Full Accordion)
    where nav = configurableNavigation (navigateColor "#ffff00")
          m = named "M"
            . lessBorders Screen
            . layoutHintsToCenter
            . addTabs shrinkText defaultTheme
            . nav
            . boringAuto
            . subLayout [] (Simplest ||| simplestFloat)
            $ mosaic 1.5 [7,5,2]

myTiled = named "Tall" $ ResizableTall 1 0.03 0.5 []
--------------------------------------------------------------
-------------------- Keys ------------------------------------
myKeys c =
    [("M-<Left>"   , withFocused $ snapMove L Nothing  )
    ,("M-<Right>"  , withFocused $ snapMove R Nothing  )
    ,("M-<Up>"     , withFocused $ snapMove U Nothing  )
    ,("M-<Down>"   , withFocused $ snapMove D Nothing  )
    ,("M-S-<Left>" , withFocused $ snapShrink R Nothing)
    ,("M-S-<Right>", withFocused $ snapGrow   R Nothing)
    ,("M-S-<Up>"   , withFocused $ snapShrink D Nothing)
    ,("M-S-<Down>" , withFocused $ snapGrow   D Nothing)

    , ("M-`", namedScratchpadAction scratchpads "workspace")
    , ("M-S-h", namedScratchpadAction scratchpads "htop")

    , ("M-l", withFocused (sendMessage . expandWindowAlt) >> sendMessage Expand)
    , ("M-h", withFocused (sendMessage . shrinkWindowAlt) >> sendMessage Shrink)

    ,("M-;", withFocused (sendMessage . tallWindowAlt) >> sendMessage Taller)
    ,("M-o", withFocused (sendMessage . wideWindowAlt) >> sendMessage Wider )

    ,("M-v", toggleFF)

    ,("M-S-b", restart "/home/aavogt/bin/obtoxmd" True)
    ,("M-S-d", restart "urxvt -e xmonad" False)

    ,("M-S-o"  , withFocused $ sendMessage . UnMerge   )
    ,("M-S-C-o", withFocused $ sendMessage . UnMergeAll)
    ,("M-C-m"  , withFocused $ sendMessage . MergeAll  )
    ,("M-C-."  , onGroup W.focusDown')
    ,("M-C-,"  , onGroup W.focusUp'  )

    ,("M-p",  shellPromptHere myXPConfig)
    ,("M-x", submap $ M.fromList subMaps)
    ,("M-g", submap $ defaultSublMap c  )

    ,("M-S-.", focusDown)
    ,("M-S-,", focusUp  )

    ,("M-S-a", currentTopicAction myTopicConfig)
    ,("M-a", warpToCentre >> goToSelected gsConfig)
    -- workaround
    ,("M-<Tab>", switchNthLastFocused myTopicConfig . succ . length . W.visible . windowset =<< get )

    ,("M-s"  , warpToCentre >> promptedGoto )
    ,("M-S-s", warpToCentre >> promptedShift)

    ,("M-b", sendMessage ToggleStruts)
    ,("M-<Return>", dwmpromote)
    ,("M-S-<Return>", spawnShell)
    -- don't force a recompile, if nothing has changed (xmonad --recompile runs XMonad.recompile True)
    ,("M-q", spawn "ghc -e ':m +XMonad Control.Monad System.Exit' -e 'flip unless exitFailure =<< recompile False' && xmonad --restart")
    ,("M-S-q", spawn "~/wip/x11-wm/xmonad/rebuild.sh")
    ,("<Print>",  spawn "scrot")
    ]
    ++
    concatMap (\(m,f) -> lrud ("M-"++m) f)
        [("S-"  , sendMessage . Swap)
        ,("C-"  , sendMessage . pullGroup)
        ,("S-C-", sendMessage . pushWindow)
        ,(""    , sendMessage . Go)]
    ++ mediaKeys ++
    [("M-"++m++[key], screenWorkspace sc >>= flip whenJust (windows . f))
        | (f, m) <- [(W.view, ""), (W.shift, "S-")]
        , (key, sc) <- zip "wf" [0 .. ]]
    ++
    [ ("M-"++m++[k], a i)
        | (a, m) <- [(switchNthLastFocused myTopicConfig,""),(shiftNthLastFocused, "S-")]
        , (i, k) <- zip [1..] "123456789"]

-- helper for windowNavigation keys
--    note: with colemak neiu are placed where jkli are with qwerty layout
lrud :: String -> (Direction2D -> b) -> [(String, b)]
lrud m cmd = zip ks cmds
    where
      ks   = map (\x -> m ++ [x]) "niue"
      cmds = zipWith ($) (repeat cmd) [L,R,U,D]

subMaps = [((0, xK_o),  runOrRaisePrompt myXPConfig),
           ((0, xK_p),  shellPromptHere myXPConfig),
           ((0, xK_x), xmonadPrompt myXPConfig),
           ((0, xK_z), sshPrompt myXPConfig),
           ((shiftMask, xK_w), windowPromptGoto myXPConfig),
           ((0, xK_w), promptSearch myXPConfig wikipedia),
           ((0, xK_s), promptSearch myXPConfig multi),
           ((0, xK_m), promptSearch myXPConfig mathworld),
           ((0, xK_b), sendMessage ToggleStruts),
           ((0, xK_f), withFocused $ windows . W.sink),
           ((0, xK_v), refresh),
           ((0, xK_c), asks config >>= spawnHere . terminal),
           ((0, xK_k), kill)
           ]


amarok = False

mediaKeys = [("<XF86AudioPlay>", do mpcAct "toggle"; when amarok $ spawn "amarok -t"),
             ("<XF86AudioStop>", promptHost),
             ("<XF86AudioNext>", do mpcAct "next"; when amarok $ spawn "amarok -f"),
             ("<XF86AudioPrev>", do mpcAct "prev"; when amarok $ spawn "amarok -r"),
             ("<XF86AudioMute>", spawn "ossmix vmix0-outvol 0"),
             ("<XF86AudioLowerVolume>",   spawn "amixer sset PCM 1-"),
             ("<XF86AudioRaiseVolume>",   spawn "amixer sset PCM 1+"),
             ("<XF86Sleep>", spawn "sudo pm-suspend")
             ]
    where mpcAct c = do
            h <- XS.gets hostPrompt
            spawn $ unwords ["export MPD_HOST="++h,";","mpc",c]

-- Prompt for mpd host
newtype HostPrompt = HostPrompt { hostPrompt :: String } deriving (Read,Show,Typeable)
instance ExtensionClass HostPrompt where
    initialValue = HostPrompt "/home/aavogt/.mpd/socket"
    extensionType = PersistentExtension

instance XPrompt HostPrompt where showXPrompt _ = "Pick MPD Host: "
promptHost = mkXPrompt (HostPrompt "") myXPConfig (return . compl) (XS.put . HostPrompt)
    where compl s = nub $ filter (s `isPrefixOf`) ["127.0.0.1","dell"]
--------------------------------------------------------------

warpToCentre = gets (W.screen . W.current . windowset) >>= \x -> warpToScreen x  0.5 0.5

-------------------- Support for per-screen xmobars ---------
-- Some parts of this should be merged into contrib sometime
getScreens :: IO [Int]
getScreens = openDisplay "" >>= liftA2 (<*) f closeDisplay
    where f = fmap (zipWith const [0..]) . getScreenInfo

multiPP :: PP -- ^ The PP to use if the screen is focused
        -> PP -- ^ The PP to use otherwise
        -> [Handle] -- ^ Handles for the status bars, in order of increasing X
                    -- screen number
        -> X ()
multiPP = multiPP' dynamicLogString

multiPP' :: (PP -> X String) -> PP -> PP -> [Handle] -> X ()
multiPP' dynlStr focusPP unfocusPP handles = do
    state <- get
    let pickPP :: WorkspaceId -> WriterT (Last XState) X String
        pickPP ws = do
            let isFoc = (ws ==) . W.tag . W.workspace . W.current $ windowset state
            put state{ windowset = W.view ws $ windowset state }
            out <- lift $ dynlStr $ if isFoc then focusPP else unfocusPP
            when isFoc $ get >>= tell . Last . Just
            return out
    traverse put . getLast
        =<< execWriterT . (io . zipWithM_ hPutStrLn handles <=< mapM pickPP) . catMaybes
        =<< mapM screenWorkspace (zipWith const [0..] handles)
    return ()

mergePPOutputs :: [PP -> X String] -> PP -> X String
mergePPOutputs x pp = fmap (intercalate (ppSep pp)) . sequence . sequence x $ pp

onlyTitle :: PP -> PP
onlyTitle pp = defaultPP { ppCurrent = const ""
                         , ppHidden = const ""
                         , ppVisible = const ""
                         , ppLayout = ppLayout pp
                         , ppTitle = ppTitle pp }

-- | Requires a recent addition to xmobar (>0.9.2), otherwise you have to use
-- multiple configuration files, which gets messy
xmobarScreen :: Int -> IO Handle
xmobarScreen = spawnPipe . ("~/.cabal/bin/xmobar -x " ++) . show

myPP :: PP
myPP = sjanssenPP { ppLayout = xmobarColor "orange" "", ppUrgent = xmobarColor "red" "" . ('^':) }
--------------------------------------------------------------

-------------------- X.Actions.TopicSpace --------------------
myTopics :: [Topic]
myTopics =
  [ "workspace"
  , "web"
  , "mail"
  , "xm-conf"
  , "test"
  ]

myTopicConfig = TopicConfig
  { topicDirs = M.fromList $
      [ ("workspace", "~/workspace")
      , ("xm-conf", ".xmonad")
      ]
  , defaultTopicAction = const $ spawnShell >*> 2
  , defaultTopic = "workspace"
  , maxTopicHistory = 10
  , topicActions = M.fromList $
      [ ("xm-conf",  spawn "~/bin/emacs ~/.xmonad/xmonad.hs")
       , ("mail"   , spawnOn "mail" "thunderbird")
       , ("web", spawnOn "web" "google-chrome")
      ]
  }

-- From the sample config in TopicSpace, these should probably be exported from that module
spawnShell = currentTopicDir myTopicConfig >>= spawnShellIn

spawnShellIn dir = do
    -- color <- randomBg' (HSV 255 255)
    t <- asks (terminal . config)
    spawnHere $ "cd " ++ dir ++ " && " ++ t -- ++ " -bg " ++ color

wsgrid = gridselect gsConfig <=< asks $ map (\x -> (x,x)) . workspaces . config

promptedGoto = wsgrid >>= flip whenJust (switchTopic myTopicConfig)

promptedShift = wsgrid >>= \x -> whenJust x $ \y -> windows (W.greedyView y . W.shift y)
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- A nice little example of extensiblestate
newtype FocusFollow = FocusFollow {getFocusFollow :: Bool } deriving (Typeable,Read,Show)
instance ExtensionClass FocusFollow where
    initialValue = FocusFollow True
    extensionType = PersistentExtension

-- this eventHook is the same as from xmonad for handling crossing events
focusFollow e@(CrossingEvent {ev_window=w, ev_event_type=t})
                | t == enterNotify, ev_mode e == notifyNormal =
        whenX (XS.gets getFocusFollow) (focus w) >> return (All True)
focusFollow _ = return (All True)

toggleFF = XS.modify $ FocusFollow . not . getFocusFollow
--------------------------------------------------------------------------------

{- | Sometimes this picks the wrong element to merge into (that is, not the
'focused' element of the group), and SubLayouts breaks up the whole group
-}
queryMerge pGrp = do
    w <- ask
    aws <- liftX $ filterM (runQuery pGrp) =<< gets
        (W.integrate' . W.stack . W.workspace . W.current . windowset)

    let addRem = False -- run the query with window removed??
    when addRem
        (liftX $ modify (\ws -> ws { windowset = W.insertUp w (windowset ws) }))
    liftX $ windows (W.insertUp w)

    mapM_ (liftX . sendMessage . XMonad.Layout.SubLayouts.Merge w) aws

    when addRem
        (liftX $ modify (\ws -> ws { windowset = W.delete' w (windowset ws) }))

    idHook

import System.Process (readProcessWithExitCode)
import System.Exit (ExitCode(ExitSuccess))
import Data.Maybe (fromMaybe)
import Control.Applicative ((<$>), (<*>))
import BranchParse (BranchInfo(MkBranchInfo), branchInfo, Distance, pairFromDistance)
import StatusParse (Status(MakeStatus), processStatus)
import Data.List (intercalate)
import System.IO.Unsafe (unsafeInterleaveIO)

{- Type aliases -}

type Hash = String
type Numbers = [String]

{- Combining branch and status parsing -}

rightOrNothing :: Either a b -> Maybe b
rightOrNothing = either (const Nothing) Just

processBranch :: String -> Maybe BranchInfo
processBranch = rightOrNothing . branchInfo . drop 3

processGitStatus :: [String] -> Maybe (BranchInfo, Status Int)
processGitStatus [] = Nothing
processGitStatus (branchLine:statusLines) = (,) <$> processBranch branchLine <*> processStatus statusLines

showStatusNumbers :: Status Int -> Numbers
showStatusNumbers (MakeStatus s x c t) = show <$> [s, x, c, t]


showBranchNumbers :: Maybe Distance -> Numbers
showBranchNumbers distance = show <$> [ahead, behind]
	where
		(ahead, behind) = fromMaybe (0,0)  -- the script needs some value, (0,0) means no display
			$ pairFromDistance <$> distance

makeHashWith :: Char -- prefix to hashes
				-> Maybe Hash
				-> String
makeHashWith _ Nothing = "" -- some error in gitrevparse
makeHashWith _ (Just "") = "" -- hash too short
makeHashWith c (Just hash) = c : init hash

{- Git commands -}

successOrNothing :: (ExitCode, a, b) -> Maybe a
successOrNothing (exitCode, output, _) =
	if exitCode == ExitSuccess then Just output else Nothing

safeRun :: String -> [String] -> IO (Maybe String)
safeRun command arguments = successOrNothing <$> readProcessWithExitCode command arguments ""

gitstatus :: IO (Maybe String)
gitstatus =   safeRun "git" ["status", "--porcelain", "--branch"]

gitrevparse :: IO (Maybe Hash)
gitrevparse = safeRun "git" ["rev-parse", "--short", "HEAD"]

{- Combine status info, branch info and hash -}

branchOrHash :: Maybe String -- Hash
				-> Maybe String -- Branch
				-> String
branchOrHash _ (Just branch) = branch
branchOrHash (Just hash) Nothing = hash
branchOrHash Nothing _ = ""

allStrings :: Maybe String -- hash
			-> (BranchInfo, Status Int) 
			-> [String]
allStrings mhash (MkBranchInfo branch _ behead, stat) = branchOrHash mhash (show <$> branch) : (showBranchNumbers behead ++ showStatusNumbers stat)

stringsFromStatus :: Maybe String -- hash
					-> String -- status
					-> Maybe [String]
stringsFromStatus h = fmap  (allStrings h) . processGitStatus . lines


{- main -}

main :: IO ()
main = do
	mstatus <- gitstatus
	mhash <- unsafeInterleaveIO gitrevparse -- defer the execution until we know we need the hash
	let result = do
		status <- mstatus
		strings <- stringsFromStatus mhash status
		return $ intercalate " " strings
	putStrLn $ fromMaybe "" result

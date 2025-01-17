{-# LANGUAGE ApplicativeDo #-}

module Config (loadConfig, Config (..), BlockFetcherConfig (..)) where

import Control.Monad.IO.Class (MonadIO)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Int (Int64)
import Data.Maybe (fromMaybe)
import Toml (TomlCodec, dimap, (.=))
import Toml qualified

import Block.Types (BlockInfo (BlockInfo), blockId, blockSlot)

data BlockFetcherConfig = BlockFetcherConfig
  { cfgFetcherBlock :: BlockInfo
  , cfgFetcherFilterJson :: LBS.ByteString
  , cfgFetcherUseLatest :: Bool
  }
  deriving stock (Show)

data Config = Config
  { cfgDbConnectionString :: ByteString
  , cfgServerPort :: Int
  , cfgOgmiosAddress :: String
  , cfgOgmiosPort :: Int
  , cfgFetcher :: Maybe BlockFetcherConfig
  }
  deriving stock (Show)

withDefault :: a -> TomlCodec a -> TomlCodec a
withDefault d c = dimap pure (fromMaybe d) (Toml.dioptional c)

int64 :: Toml.Key -> TomlCodec Int64
int64 k = dimap fromIntegral fromIntegral (Toml.integer k)

matchTrue :: Toml.Value t -> Either Toml.MatchError Bool
matchTrue (Toml.Bool True) = Right True
matchTrue value = Toml.mkMatchError Toml.TBool value

true :: Toml.Key -> TomlCodec Bool
true = Toml.match $ Toml.mkAnyValueBiMap matchTrue Toml.Bool

blockInfoT :: TomlCodec BlockInfo
blockInfoT = do
  blockSlot' <-
    int64 "blockFetcher.firstBlock.slot"
      .= blockSlot
  blockId' <-
    Toml.text "blockFetcher.firstBlock.id"
      .= blockId
  pure $ BlockInfo blockSlot' blockId'

withFetcherT :: TomlCodec BlockFetcherConfig
withFetcherT = do
  true "blockFetcher.autoStart" .= const True
  -- bool b Nothing Nothing
  cfgFetcherFilterJson <-
    withDefault "{ \"const\" = true  }" (Toml.lazyByteString "blockFetcher.filter")
      .= cfgFetcherFilterJson
  cfgFetcherBlock <- blockInfoT .= cfgFetcherBlock
  cfgFetcherUseLatest <-
    withDefault False (Toml.bool "blockFetcher.startFromLast")
      .= cfgFetcherUseLatest
  pure BlockFetcherConfig {..}

configT :: TomlCodec Config
configT = do
  cfgDbConnectionString <- Toml.byteString "dbConnectionString" .= cfgDbConnectionString
  cfgServerPort <- Toml.int "server.port" .= cfgServerPort
  cfgOgmiosAddress <- Toml.string "ogmios.address" .= cfgOgmiosAddress
  cfgOgmiosPort <- Toml.int "ogmios.port" .= cfgOgmiosPort
  cfgFetcher <- Toml.dioptional withFetcherT .= cfgFetcher
  pure Config {..}

loadConfig :: MonadIO m => m Config
loadConfig = Toml.decodeFile configT "config.toml"

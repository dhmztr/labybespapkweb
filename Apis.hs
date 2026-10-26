{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}
module Apis where

import Types
import Control.Concurrent (modifyMVar_)
import Control.Concurrent.MVar
import Control.Exception (try)
import Control.Monad.IO.Class (MonadIO (liftIO))
import Crypto.Random (MonadRandom (getRandomBytes))
import Data.Aeson
import Data.ByteString qualified as BS
import Data.ByteString.Lazy.Char8 qualified as BL8
import Data.Char (intToDigit)
import Data.Map qualified as M
import Data.Password.Argon2
import Data.Swagger (Swagger, ToSchema)
import Data.Text qualified as T
import Database.PostgreSQL.Simple
import GHC.Generics (Generic)
import Network.Wai.Handler.Warp (run)
import Numeric (showIntAtBase)
import Servant
import Servant.Swagger (toSwagger)
import Servant.Swagger.UI (SwaggerSchemaUI, swaggerSchemaUIServer)
import Data.List (stripPrefix)


passwordHash :: PasswordHash Argon2
passwordHash = PasswordHash "$argon2id$v=19$m=65536,t=2,p=1$PycdySns1NErahSML9ctNA$9HDgpC/b2j+us2dCmsrSnK4CRv3bHTYinpGDh10KM/0"
zamowienie :: MVar (M.Map String String) -> Maybe String -> Zamowienie -> (Handler ZamowienieOdpowiedz)
zamowienie mv naglowek zamowieniereq = case naglowek of
    (Just rawtok) -> do
        case (stripPrefix "Bearer " rawtok) of
            Just x -> do
                mapa <- liftIO (readMVar mv)
                case (M.lookup x mapa) of
                    (Just _) -> do
                        case zweryfikujZamowienie (adres_startowy zamowieniereq) (adres_docelowy zamowieniereq) (miejsca zamowieniereq) of
                            Right _zamowienieOk -> do
                                let odpowiedz = ZamowienieOdpowiedz "kierowca1"
                                return odpowiedz
                            Left powod -> throwError (err400{errBody = (BL8.pack ("Nie mozna ukonczyc zamowienia: " ++ powod))})
                    Nothing -> throwError (err401{errBody = BL8.pack ("Wygasly token ")})
            Nothing -> throwError err401
    Nothing -> throwError (err401{errBody = (BL8.pack "Brak tokenu autoryzujacego")})
rejestracja :: MVar (M.Map String String) -> Connection -> Poswiadczenia -> (Handler Odpowiedz)
rejestracja mv conn user = do
    let zapytanie = "INSERT INTO users (email,password_hash) Values (?,?)"
    hash_haslo <- hashPassword $ (mkPassword (T.pack (haslo user)))
    operacja <- liftIO (try (execute conn zapytanie (email user, unPasswordHash (hash_haslo))))
    case operacja of
        Left (e :: SqlError)
            | sqlState e == "23505" -> throwError err409{errBody = (BL8.pack ("Uzytkownik istnieje"))}
            | otherwise -> throwError err500{errBody = (BL8.pack ("Nie udalo sie stworzyc konta"))}
        (Right _) -> do
            tok <- liftIO (generujToken)
            liftIO (modifyMVar_ mv (\mapa -> pure (M.insert tok (email user) mapa)))
            pure (Odpowiedz tok)
login :: MVar (M.Map String String) -> Connection -> Poswiadczenia -> (Handler Odpowiedz)
login mv conn user = do
    rows <- (liftIO (query conn "SELECT password_hash FROM users WHERE email = ?" (Only (email user)) :: IO [Only T.Text]))
    let (hash, istnieje) = case rows of
            (Only h : _) -> ((PasswordHash h), True)
            [] -> (passwordHash, False)
    if ((checkPassword (mkPassword (T.pack (haslo user))) hash) == PasswordCheckSuccess) && istnieje
        then do
            token <- liftIO generujToken
            liftIO (modifyMVar_ mv (\mapa -> pure (M.insert token (email user) mapa)))
            return (Odpowiedz token)
        else
            throwError err401

zdrowie :: (Handler String)
zdrowie = return "ok"
ja :: MVar (M.Map String String) -> Maybe String -> Handler String
ja mv head = case head of
    Just x -> do
        case (stripPrefix "Bearer " x ) of
            Just tok -> do 
                mapa <- liftIO (readMVar mv)
                maybe (throwError err401) return (M.lookup tok mapa)
            Nothing -> throwError err401 
    Nothing -> throwError err401
wyloguj :: MVar (M.Map String String) -> Maybe String -> (Handler String) 
wyloguj mv authtoken = case authtoken of 
                                Just tok -> do
                                        let strippedToken = stripPrefix "Bearer " tok 
                                        case strippedToken  of 
                                            Just validtoken -> do
                                                liftIO (modifyMVar_ mv (\mapa -> pure (M.delete validtoken mapa)))
                                                pure "OK"
                                            Nothing -> throwError  err401 
                                Nothing -> throwError err401 
            

generujToken :: IO String
generujToken = do
  bytesarr <- getRandomBytes 32 :: IO BS.ByteString
  let intarr = map fromIntegral (BS.unpack bytesarr)
  let hex = concatMap byteToHex intarr
  pure hex

byteToHex :: Int -> String
byteToHex number
  | length wynik == 1 = "0" ++ wynik
  | otherwise = wynik
 where
  wynik = showIntAtBase 16 intToDigit number ""


zweryfikujZamowienie :: String -> String -> Int -> Either String Zamowienie
zweryfikujZamowienie x y z
  | null x = Left "Niepoprawny adres startowy"
  | null y = Left "Niepoprawna destynacja"
  | (z > 4) || (z < 1) = Left "Ilosc pasazerow poza zasiegiem"
  | otherwise = Right (Zamowienie x y z)

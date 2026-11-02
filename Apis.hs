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
import Data.List (stripPrefix, minimumBy)
import GHC.Base (Float)
import Types (Kierowca (lat, lon))
import Data.Function (on)
import Cars (znajdzKierowce)
import Data.Time.Clock (getCurrentTime)
import Text.HTML.SanitizeXSS (sanitize)


passwordHash :: PasswordHash Argon2
passwordHash = PasswordHash "$argon2id$v=19$m=65536,t=2,p=1$PycdySns1NErahSML9ctNA$9HDgpC/b2j+us2dCmsrSnK4CRv3bHTYinpGDh10KM/0"
kierowcy :: MVar (M.Map String Kierowca) -> Handler ([Kierowca])
kierowcy mv = do
                inner <- liftIO (readMVar mv)

                return (M.elems inner)
zamowienie :: MVar (M.Map String String) -> MVar (M.Map String String) -> MVar (M.Map String Kierowca) -> Maybe String -> Zamowienie -> (Handler Kierowca)
zamowienie mvtokeny mvprzejazdy mvkierowcy naglowek zamowieniereq = case naglowek of
    (Just rawtok) -> do
        case (stripPrefix "Bearer " rawtok) of
            Just x -> do
                mapa <- liftIO (readMVar mvtokeny)
                case (M.lookup x mapa) of
                    (Just usermail) -> do
                        przejazdy <- liftIO (readMVar mvprzejazdy )
                        let mtokenAktywny = M.lookup usermail przejazdy 
                        dozwolone <- case mtokenAktywny of
                            Nothing -> return True
                            Just idkier -> do
                                mapaKierowcow <- liftIO (readMVar mvkierowcy)
                                case M.lookup idkier mapaKierowcow of
                                    Just k  -> return (cel k == Nothing)   -- skonczyl = wolno nowy
                                    Nothing -> return True


                                                            

                        if not dozwolone 
                            then throwError err409 
                        else
                         case zweryfikujZamowienie (lat_startowy zamowieniereq) (lon_startowy zamowieniereq) (lat_koncowy zamowieniereq ) (lon_koncowy zamowieniereq ) (miejsca zamowieniereq) of
                            Right zamowienieOk -> do
                                            kierowcymap <-(liftIO (readMVar mvkierowcy ))
                                            let kierowcy = M.elems kierowcymap 
                                        
                                            let kierowca = (znajdzKierowce ((lat_startowy zamowienieOk ) ,(lon_startowy zamowienieOk)) (miejsca zamowienieOk) kierowcy)
                                            liftIO (modifyMVar_ mvprzejazdy (\mapa -> pure (M.insert usermail (idKierowcy kierowca) mapa)))
                                            let zmodyfikowany = Kierowca (idKierowcy kierowca ) (lat kierowca) (lon kierowca ) (Just ((lat_koncowy zamowienieOk ),(lon_koncowy zamowienieOk ))) (wolne_miejsca kierowca )
                                            liftIO (modifyMVar_ mvkierowcy (\mapa -> pure (M.insert (idKierowcy kierowca) zmodyfikowany mapa ) ))
                                            return zmodyfikowany 
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
ja mv header = case header of
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
            
komentarzedlakierowcy ::  MVar (M.Map String String) -> Connection -> Maybe String -> KomentarzReq -> (Handler [Komentarz])
komentarzedlakierowcy mv conn authtoken req = do
                        case authtoken of 
                            Nothing -> throwError err401 
                            Just (tok) -> do 
                                let strippedToken = stripPrefix "Bearer " tok 
                                case strippedToken  of
                                 Nothing -> throwError err401 
                                 (Just validToken ) -> do 
                                            innermap <- liftIO (readMVar mv)
                                            case M.lookup validToken innermap of 
                                                Nothing -> throwError err401 
                                                (Just _) -> do
                                                        
                                                    let idk = reqidkier req
                                                    queryresp <- (liftIO (query conn "SELECT idKier,data,ocena,wystawiajacy,tresc FROM komentarze WHERE idKier = ?" (Only idk) :: IO [(String,String,Double,String, String)]))
                                                    let komentarze = map (\(x, y, z,a, b) -> zparsujkomentarze (x, y, z, a,b)) queryresp
                                                    return komentarze
                    
dodajKomentarz :: MVar (M.Map String String) -> Connection -> Maybe String -> Komentarz -> (Handler String)
dodajKomentarz mv conn authtoken kom = do
                    case authtoken of
                        Nothing -> throwError err401
                        Just (tok) -> do
                                    let strippedToken = stripPrefix "Bearer " tok 
                                    case strippedToken of
                                        (Just validToken) -> do
                                            innermap <- liftIO (readMVar mv )
                                            case M.lookup validToken innermap of
                                                Nothing -> throwError err401 
                                                (Just wystawiajacyemail) ->  do
                                                    let zapytanie = "INSERT INTO komentarze (idKier,data,ocena,wystawiajacy,tresc) Values (?,?,?,?,?)"
                                                    aktualna_data <- liftIO (getCurrentTime )
                                                    let zweryfikowany = zweryfikujKomentarz (idKier kom) (show aktualna_data ) (ocena kom) wystawiajacyemail (tresc kom )
                                                    case zweryfikowany  of
                                                        (Left powod) -> throwError err406 {errBody = BL8.pack (powod )}
                                                        (Right poprawnykom) -> do

                                                            operacja <- liftIO (try (execute conn zapytanie ((idKier poprawnykom) ,(czasotrzymania poprawnykom ),(ocena poprawnykom),wystawiajacyemail , tresc poprawnykom)))
                                                            case operacja  of
                                                             Left (e :: SqlError ) -> throwError err500 
                                                             (Right _) ->  return "OK"
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


zweryfikujZamowienie :: Double -> Double -> Double -> Double -> Int -> Either String Zamowienie
zweryfikujZamowienie las los lak lok z 
  | las < 0 = Left "Niepoprawny adres startowy"
  | los < 0 = Left "Niepoprawny adres startowy"
  | lok < 0 = Left "Niepoprawny adres docelowy"
  | lak < 0 = Left "Niepoprawny adres docelowy"
  | (z > 4) || (z < 1) = Left "Ilosc pasazerow poza zasiegiem"
  | otherwise = Right (Zamowienie las los lak lok z)
zparsujkomentarze:: (String,String,Double,String,String) -> Komentarz
zparsujkomentarze (a, b, c, d,e) = Komentarz {idKier = a,czasotrzymania=b,ocena=c,wystawiajacy=d,tresc=e}

zweryfikujKomentarz :: String -> String -> Double -> String -> String -> Either String Komentarz
zweryfikujKomentarz idk datakom ocenakier wystawiajacykom tresckom 
    | null idk || length idk > 30 = Left "Niepoprawny kierowca"
    | null datakom || length datakom > 50 = Left "Niepoprawna data"
    | ocenakier > 5 || ocenakier < 0 = Left "Niepoprawna ocena"
    | null wystawiajacykom || length wystawiajacykom > 30 = Left "Niepoprawny wystawiajacy"
    | null tresckom || length tresckom > 500 = Left "Niepoprawna tresc komentarza"
    | otherwise = Right (Komentarz {idKier = sanitizeString idk,czasotrzymania=datakom ,ocena = ocenakier ,wystawiajacy= sanitizeString (wystawiajacykom ),tresc = sanitizeString (tresckom)})

                                    
    
                                
sanitizeString :: String -> String
sanitizeString wartosc = T.unpack (sanitize (T.pack wartosc ))
    

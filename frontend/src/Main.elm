port module Main exposing (main)

import Browser
import Browser.Dom
import Dict exposing (Dict)
import Html exposing (Html, a, button, dd, details, div, dl, dt, figcaption, figure, footer, form, h1, h2, h3, header, img, input, label, li, main_, nav, node, option, p, section, select, span, summary, text, textarea, ul)
import Html.Attributes exposing (alt, attribute, autocomplete, class, classList, disabled, for, height, href, id, maxlength, required, rows, selected, spellcheck, src, style, title, type_, value, width)
import Html.Events exposing (on, onClick, onInput, onSubmit)
import Http
import Json.Decode as D
import Json.Encode as E
import Task
import Time


port zapiszToken : String -> Cmd msg


port usunToken : () -> Cmd msg


{-| auta, które użytkownik może ocenić, zapamiętane w localStorage: { email: [id auta] }
-}
port zapiszOceny : E.Value -> Cmd msg


{-| flagi: { token: zapamiętany token albo null, oceny: to, co zapisał port zapiszOceny }
-}
main : Program D.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


{-| lista aut jest publiczna, więc odświeża się co 2 sekundy także na stronie głównej
-}
subscriptions : Model -> Sub Msg
subscriptions _ =
    Time.every 2000 Tik



-- MODEL


type alias Model =
    { email : String
    , haslo : String
    , powtorz : String
    , tryb : Tryb
    , stan : Stan
    , flota : List Kierowca
    , pytanie : String
    , oceny : Dict String (List String)
    }


type Tryb
    = Logowanie
    | Rejestracja


type Stan
    = Formularz (Maybe String)
    | Wysylanie
    | Sprawdzanie
    | Wylogowany
    | Zalogowany Sesja


{-| wszystko, co aplikacja pamięta po zalogowaniu
-}
type alias Sesja =
    { email : String
    , token : String
    , strona : Strona
    , wybrane : Maybe String
    , zam : FormZamowienia
    , kom : FormKomentarzy
    , przejazd : Maybe String
    , doOceny : List String
    , zakonczony : Maybe String
    , wersja : Int
    , historia : Historia
    }


{-| odpowiedź /ja: e-mail i id auta, jeśli użytkownik ma teraz aktywny przejazd
-}
type alias Ja =
    { email : String
    , przejazd : Maybe String
    }


type Strona
    = StronaAuta
    | StronaZamowienie
    | StronaPrzejazdy
    | StronaKomentarze


{-| cel to punkt, do którego auto jedzie teraz; celKoncowy jest ustawiony tylko wtedy,
gdy auto jedzie jeszcze po klienta (cel = odbiór, celKoncowy = miejsce docelowe)
-}
type alias Kierowca =
    { id : String
    , lat : Float
    , lon : Float
    , cel : Maybe ( Float, Float )
    , celKoncowy : Maybe ( Float, Float )
    , wolne : Int
    }


type EtapKursu
    = Wolne
    | PoKlienta ( Float, Float ) ( Float, Float )
    | DoCelu ( Float, Float )


etapAuta : Kierowca -> EtapKursu
etapAuta k =
    case ( k.cel, k.celKoncowy ) of
        ( Just odbior, Just meta ) ->
            PoKlienta odbior meta

        ( Just meta, Nothing ) ->
            DoCelu meta

        ( Nothing, _ ) ->
            Wolne


type Punkt
    = Start
    | Cel


type Pole
    = StartLat
    | StartLon
    | CelLat
    | CelLon


type alias FormZamowienia =
    { startLat : String
    , startLon : String
    , celLat : String
    , celLon : String
    , miejsca : String
    , ustawiam : Punkt
    , stan : StanZam
    }


type StanZam
    = ZamPisanie (Maybe String)
    | ZamWysylanie


type alias Komentarz =
    { autor : String
    , data : String
    , ocena : Float
    , tresc : String
    }


type Lista
    = ListaPusta
    | ListaLaduje
    | ListaGotowa (List Komentarz)
    | ListaBlad


{-| jeden wiersz z /mojeprzejazdy; auto to vehicle_id zamienione na tekst, tak jak id aut w reszcie aplikacji
-}
type alias Przejazd =
    { auto : String
    , startLat : Float
    , startLon : Float
    , celLat : Float
    , celLon : Float
    , status : String
    , data : String
    }


type Historia
    = HistoriaPusta
    | HistoriaLaduje
    | HistoriaGotowa (List Przejazd)
    | HistoriaBlad


type alias FormKomentarzy =
    { wybrany : Maybe String
    , lista : Lista
    , ocena : String
    , tresc : String
    , wysylanie : Bool
    , blad : Maybe String
    , info : Maybe String
    }


pustaZamowienie : FormZamowienia
pustaZamowienie =
    { startLat = ""
    , startLon = ""
    , celLat = ""
    , celLon = ""
    , miejsca = "1"
    , ustawiam = Start
    , stan = ZamPisanie Nothing
    }


puste : FormKomentarzy
puste =
    { wybrany = Nothing
    , lista = ListaPusta
    , ocena = "5"
    , tresc = ""
    , wysylanie = False
    , blad = Nothing
    , info = Nothing
    }


{-| z aktywnym przejazdem od razu pokazujemy zakładkę zamówienia
-}
nowaSesja : Model -> String -> Ja -> Sesja
nowaSesja model token ja =
    { email = ja.email
    , token = token
    , strona =
        if ja.przejazd == Nothing then
            StronaAuta

        else
            StronaZamowienie
    , wybrane = Nothing
    , zam = pustaZamowienie
    , kom = puste
    , przejazd = ja.przejazd
    , doOceny = Maybe.withDefault [] (Dict.get ja.email model.oceny)
    , zakonczony = Nothing
    , wersja = 0
    , historia = HistoriaPusta
    }


poczatek : Model
poczatek =
    { email = ""
    , haslo = ""
    , powtorz = ""
    , tryb = Logowanie
    , stan = Formularz Nothing
    , flota = []
    , pytanie = "nas jest troje"
    , oceny = Dict.empty
    }


init : D.Value -> ( Model, Cmd Msg )
init flagi =
    let
        zapamietany =
            Result.withDefault Nothing (D.decodeValue (D.field "token" (D.nullable D.string)) flagi)

        oceny =
            Result.withDefault Dict.empty (D.decodeValue (D.field "oceny" (D.dict (D.list D.string))) flagi)

        model =
            { poczatek | oceny = oceny }
    in
    case zapamietany of
        Just token ->
            -- sesja z poprzedniej wizyty: sprawdzamy u backendu, czy token nadal działa
            ( { model | stan = Sprawdzanie }, Cmd.batch [ przywroc token, pobierzKierowcow ] )

        Nothing ->
            ( model, pobierzKierowcow )


{-| wraca do strony głównej, ale zostawia flotę i to, co ktoś wpisał w pytanie
-}
doStronyGlownej : Stan -> Model -> Model
doStronyGlownej stan model =
    { model | email = "", haslo = "", powtorz = "", tryb = Logowanie, stan = stan }



-- UPDATE


type Msg
    = WpisanoEmail String
    | WpisanoHaslo String
    | WpisanoPowtorz String
    | UstawTryb Tryb
    | Zaloguj
    | Zarejestruj
    | OdpowiedzLogin (Result Http.Error String)
    | OdpowiedzRejestracja (Result Http.Error String)
    | OdpowiedzJa String (Result Http.Error Ja)
    | OdpowiedzPrzywrocenie String (Result Http.Error Ja)
    | OdpowiedzStanu Int (Result Http.Error Ja)
    | ZamknijKomunikat
    | Wyloguj
    | OdpowiedzWyloguj (Result Http.Error ())
    | NicNieRob
      -- strona główna
    | WpisanoPytanie String
      -- aplikacja po zalogowaniu
    | Tik Time.Posix
    | OdpowiedzKierowcy (Result Http.Error (List Kierowca))
    | IdzDo Strona
    | WybranoAuto String
    | OtworzOpinie String
      -- zamówienie
    | WpisanoWsp Pole String
    | UstawPunkt Punkt
    | KlikMapa Float Float
    | WpisanoMiejsca String
    | Zamow
    | OdpowiedzZamowienie (Result Http.Error Kierowca)
    | NoweZamowienie
      -- przejazdy
    | OdpowiedzPrzejazdy (Result Http.Error (List Przejazd))
      -- opinie
    | WybranoKierowce String
    | OdpowiedzKomentarze String (Result Http.Error (List Komentarz))
    | WpisanoOcene String
    | WpisanoTresc String
    | WystawKomentarz
    | OdpowiedzWystawienia (Result Http.Error ())


{-| po każdej zmianie sprawdzamy, czy lista aut do oceny się zmieniła, i jeśli tak,
zapisujemy ją w localStorage, żeby przeżyła odświeżenie strony
-}
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        ( nowy, cmd ) =
            przetworz msg model
    in
    case nowy.stan of
        Zalogowany s ->
            if Maybe.withDefault [] (Dict.get s.email nowy.oceny) == s.doOceny then
                ( nowy, cmd )

            else
                let
                    oceny =
                        if List.isEmpty s.doOceny then
                            Dict.remove s.email nowy.oceny

                        else
                            Dict.insert s.email s.doOceny nowy.oceny
                in
                ( { nowy | oceny = oceny }
                , Cmd.batch [ cmd, zapiszOceny (E.dict identity (E.list E.string) oceny) ]
                )

        _ ->
            ( nowy, cmd )


przetworz : Msg -> Model -> ( Model, Cmd Msg )
przetworz msg model =
    case msg of
        WpisanoEmail email ->
            ( { model | email = email }, Cmd.none )

        WpisanoHaslo haslo ->
            ( { model | haslo = haslo }, Cmd.none )

        WpisanoPowtorz powtorz ->
            ( { model | powtorz = powtorz }, Cmd.none )

        UstawTryb tryb ->
            ( { model | tryb = tryb, haslo = "", powtorz = "", stan = Formularz Nothing }
            , Cmd.none
            )

        Zaloguj ->
            ( { model | stan = Wysylanie }, zaloguj model.email model.haslo )

        Zarejestruj ->
            if model.haslo /= model.powtorz then
                ( { model | stan = Formularz (Just "Hasła nie są takie same.") }, Cmd.none )

            else
                ( { model | stan = Wysylanie }, zarejestruj model.email model.haslo )

        OdpowiedzLogin (Ok token) ->
            ( model, pobierzJa token )

        OdpowiedzLogin (Err blad) ->
            ( { model | stan = Formularz (Just (opisBledu blad)) }, Cmd.none )

        OdpowiedzRejestracja (Ok token) ->
            -- backend po rejestracji od razu zwraca token, więc logujemy jak po /login
            ( model, pobierzJa token )

        OdpowiedzRejestracja (Err blad) ->
            ( { model | stan = Formularz (Just (opisBledu blad)) }, Cmd.none )

        OdpowiedzJa token (Ok ja) ->
            ( { model | haslo = "", powtorz = "", stan = Zalogowany (nowaSesja model token ja) }
            , Cmd.batch [ zapiszToken token, naGore ]
            )

        OdpowiedzJa _ (Err blad) ->
            ( { model | stan = Formularz (Just (opisBledu blad)) }, Cmd.none )

        OdpowiedzPrzywrocenie token (Ok ja) ->
            ( { model | stan = Zalogowany (nowaSesja model token ja) }, Cmd.none )

        OdpowiedzPrzywrocenie _ (Err (Http.BadStatus 401)) ->
            -- token wygasł albo został unieważniony
            ( { model | stan = Formularz Nothing }, usunToken () )

        OdpowiedzPrzywrocenie _ (Err blad) ->
            ( { model | stan = Formularz (Just (opisBledu blad)) }, Cmd.none )

        Wyloguj ->
            case model.stan of
                Zalogowany dane ->
                    -- lokalnie wylogowujemy od razu, nie czekając na backend
                    ( doStronyGlownej Wylogowany model
                    , Cmd.batch [ usunToken (), wylogujNaSerwerze dane.token, przewinDo "konto" ]
                    )

                _ ->
                    ( model, Cmd.none )

        OdpowiedzWyloguj _ ->
            ( model, Cmd.none )

        NicNieRob ->
            ( model, Cmd.none )

        WpisanoPytanie pytanie ->
            ( { model | pytanie = pytanie }, Cmd.none )

        Tik _ ->
            case model.stan of
                Zalogowany s ->
                    -- zalogowanemu sprawdzamy też /ja, bo tylko stamtąd wiadomo, czy przejazd trwa
                    ( model, Cmd.batch [ pobierzKierowcow, pobierzStan s.token s.wersja ] )

                _ ->
                    ( model, pobierzKierowcow )

        OdpowiedzStanu wersja (Ok ja) ->
            zSesja
                (\s ->
                    if wersja /= s.wersja then
                        -- odpowiedź na pytanie wysłane przed złożeniem zamówienia, już nieaktualna
                        ( s, Cmd.none )

                    else
                        case ( s.przejazd, ja.przejazd ) of
                            ( Just id, Nothing ) ->
                                -- backend zapomniał przejazd: auto dowiozło klienta, można je ocenić
                                ( { s | przejazd = Nothing, zakonczony = Just id, doOceny = id :: List.filter ((/=) id) s.doOceny }
                                , Cmd.none
                                )

                            ( _, nowy ) ->
                                ( { s | przejazd = nowy }, Cmd.none )
                )
                model

        OdpowiedzStanu _ (Err (Http.BadStatus 401)) ->
            sesjaWygasla model

        OdpowiedzStanu _ (Err _) ->
            ( model, Cmd.none )

        ZamknijKomunikat ->
            zSesja (\s -> ( { s | zakonczony = Nothing }, Cmd.none )) model

        OdpowiedzKierowcy (Ok lista) ->
            ( { model | flota = List.sortBy numerAuta lista }, Cmd.none )

        OdpowiedzKierowcy (Err _) ->
            -- lista odświeża się co 2 s, więc chwilowy błąd po prostu zostawia stare dane
            ( model, Cmd.none )

        IdzDo strona ->
            zSesja
                (\s ->
                    if strona == StronaPrzejazdy then
                        -- historię pobieramy przy każdym wejściu w zakładkę, więc zawsze jest aktualna
                        ( { s | strona = strona, historia = HistoriaLaduje }, pobierzPrzejazdy s.token )

                    else
                        ( { s | strona = strona }, Cmd.none )
                )
                model

        WybranoAuto id ->
            zSesja
                (\s ->
                    if s.strona == StronaKomentarze then
                        wybierzKierowce id { s | wybrane = Just id }

                    else
                        ( { s | wybrane = Just id }, Cmd.none )
                )
                model

        OtworzOpinie id ->
            zSesja
                (\s ->
                    let
                        ( s2, cmd ) =
                            wybierzKierowce id s
                    in
                    ( { s2 | strona = StronaKomentarze, wybrane = Just id }, cmd )
                )
                model

        WpisanoWsp pole wartosc ->
            zSesja (\s -> ( { s | zam = ustawPole pole wartosc s.zam }, Cmd.none )) model

        UstawPunkt punkt ->
            zSesja (\s -> let z = s.zam in ( { s | zam = { z | ustawiam = punkt } }, Cmd.none )) model

        KlikMapa lat lon ->
            zSesja
                (\s ->
                    let
                        z =
                            s.zam
                    in
                    case z.ustawiam of
                        Start ->
                            -- po ustawieniu startu przełączamy się od razu na cel
                            ( { s | zam = { z | startLat = zaokr4 lat, startLon = zaokr4 lon, ustawiam = Cel } }, Cmd.none )

                        Cel ->
                            ( { s | zam = { z | celLat = zaokr4 lat, celLon = zaokr4 lon } }, Cmd.none )
                )
                model

        WpisanoMiejsca miejsca ->
            zSesja (\s -> let z = s.zam in ( { s | zam = { z | miejsca = miejsca } }, Cmd.none )) model

        Zamow ->
            zSesja
                (\s ->
                    let
                        z =
                            s.zam
                    in
                    case Maybe.map5 (zamow s.token) (parsuj z.startLat) (parsuj z.startLon) (parsuj z.celLat) (parsuj z.celLon) (String.toInt z.miejsca) of
                        Just cmd ->
                            ( { s | zam = { z | stan = ZamWysylanie }, wersja = s.wersja + 1 }, cmd )

                        Nothing ->
                            ( { s | zam = { z | stan = ZamPisanie (Just "Podaj poprawne współrzędne albo kliknij na mapie.") } }, Cmd.none )
                )
                model

        OdpowiedzZamowienie (Ok kierowca) ->
            zSesja
                (\s ->
                    let
                        z =
                            s.zam
                    in
                    ( { s | zam = { z | stan = ZamPisanie Nothing }, przejazd = Just kierowca.id, zakonczony = Nothing, wersja = s.wersja + 1 }
                    , Cmd.none
                    )
                )
                model

        OdpowiedzZamowienie (Err (Http.BadStatus 401)) ->
            sesjaWygasla model

        OdpowiedzZamowienie (Err blad) ->
            zSesja (\s -> let z = s.zam in ( { s | zam = { z | stan = ZamPisanie (Just (opisBleduZamowienia blad)) } }, Cmd.none )) model

        NoweZamowienie ->
            zSesja (\s -> ( { s | zam = pustaZamowienie }, Cmd.none )) model

        OdpowiedzPrzejazdy (Err (Http.BadStatus 401)) ->
            sesjaWygasla model

        OdpowiedzPrzejazdy wynik ->
            zSesja
                (\s ->
                    case wynik of
                        Ok lista ->
                            ( { s | historia = HistoriaGotowa lista }, Cmd.none )

                        Err _ ->
                            ( { s | historia = HistoriaBlad }, Cmd.none )
                )
                model

        WybranoKierowce id ->
            zSesja (wybierzKierowce id) model

        OdpowiedzKomentarze _ (Err (Http.BadStatus 401)) ->
            sesjaWygasla model

        OdpowiedzKomentarze id wynik ->
            zSesja
                (\s ->
                    let
                        k =
                            s.kom
                    in
                    -- odpowiedź dla auta, które użytkownik już zmienił, ignorujemy
                    if k.wybrany /= Just id then
                        ( s, Cmd.none )

                    else
                        case wynik of
                            Ok lista ->
                                ( { s | kom = { k | lista = ListaGotowa lista } }, Cmd.none )

                            Err _ ->
                                ( { s | kom = { k | lista = ListaBlad } }, Cmd.none )
                )
                model

        WpisanoOcene ocena ->
            zSesja (\s -> let k = s.kom in ( { s | kom = { k | ocena = ocena } }, Cmd.none )) model

        WpisanoTresc tresc ->
            zSesja (\s -> let k = s.kom in ( { s | kom = { k | tresc = tresc } }, Cmd.none )) model

        WystawKomentarz ->
            zSesja
                (\s ->
                    let
                        k =
                            s.kom
                    in
                    case k.wybrany of
                        Nothing ->
                            ( { s | kom = { k | blad = Just "Najpierw wybierz auto.", info = Nothing } }, Cmd.none )

                        Just id ->
                            if not (List.member id s.doOceny) then
                                ( { s | kom = { k | blad = Just "Opinię wystawisz po zakończonym przejeździe tym autem.", info = Nothing } }, Cmd.none )

                            else if String.trim k.tresc == "" then
                                ( { s | kom = { k | blad = Just "Wpisz treść opinii.", info = Nothing } }, Cmd.none )

                            else
                                ( { s | kom = { k | wysylanie = True, blad = Nothing, info = Nothing } }
                                , wystawKomentarz s.token id (Maybe.withDefault 5 (String.toFloat k.ocena)) k.tresc
                                )
                )
                model

        OdpowiedzWystawienia (Ok ()) ->
            zSesja
                (\s ->
                    let
                        k =
                            s.kom
                    in
                    -- jeden przejazd to jedna opinia: auto znika z listy do oceny
                    ( { s
                        | kom = { k | wysylanie = False, tresc = "", info = Just "Dziękujemy za opinię." }
                        , doOceny = List.filter (\id -> Just id /= k.wybrany) s.doOceny
                        , zakonczony = if s.zakonczony == k.wybrany then Nothing else s.zakonczony
                      }
                    , case k.wybrany of
                        Just id ->
                            pobierzKomentarze s.token id

                        Nothing ->
                            Cmd.none
                    )
                )
                model

        OdpowiedzWystawienia (Err (Http.BadStatus 401)) ->
            sesjaWygasla model

        OdpowiedzWystawienia (Err blad) ->
            zSesja
                (\s ->
                    let
                        k =
                            s.kom
                    in
                    ( { s | kom = { k | wysylanie = False, blad = Just (opisBleduOpinii blad) } }, Cmd.none )
                )
                model


{-| zmienia coś w sesji tylko wtedy, gdy ktoś jest zalogowany; w innych stanach nic nie robi
-}
zSesja : (Sesja -> ( Sesja, Cmd Msg )) -> Model -> ( Model, Cmd Msg )
zSesja zmiana model =
    case model.stan of
        Zalogowany sesja ->
            let
                ( nowa, cmd ) =
                    zmiana sesja
            in
            ( { model | stan = Zalogowany nowa }, cmd )

        _ ->
            ( model, Cmd.none )


{-| backend odpowiedział 401: token nie działa, wracamy do logowania
-}
sesjaWygasla : Model -> ( Model, Cmd Msg )
sesjaWygasla model =
    ( doStronyGlownej (Formularz (Just "Sesja wygasła. Zaloguj się ponownie.")) model
    , Cmd.batch [ usunToken (), przewinDo "konto" ]
    )


naGore : Cmd Msg
naGore =
    Task.perform (\_ -> NicNieRob) (Browser.Dom.setViewport 0 0)


{-| Browser.Dom czeka na narysowanie widoku, więc sekcja już istnieje, gdy jej szukamy
-}
przewinDo : String -> Cmd Msg
przewinDo idSekcji =
    Browser.Dom.getElement idSekcji
        |> Task.andThen (\e -> Browser.Dom.setViewport 0 e.element.y)
        |> Task.attempt (\_ -> NicNieRob)


wybierzKierowce : String -> Sesja -> ( Sesja, Cmd Msg )
wybierzKierowce id s =
    let
        k =
            s.kom
    in
    if id == "" then
        ( { s | kom = { k | wybrany = Nothing, lista = ListaPusta, blad = Nothing, info = Nothing } }, Cmd.none )

    else
        ( { s | kom = { k | wybrany = Just id, lista = ListaLaduje, blad = Nothing, info = Nothing } }
        , pobierzKomentarze s.token id
        )


ustawPole : Pole -> String -> FormZamowienia -> FormZamowienia
ustawPole pole wartosc z =
    case pole of
        StartLat ->
            { z | startLat = wartosc }

        StartLon ->
            { z | startLon = wartosc }

        CelLat ->
            { z | celLat = wartosc }

        CelLon ->
            { z | celLon = wartosc }


{-| akceptuje i kropkę, i przecinek: "51,1" i "51.1"
-}
parsuj : String -> Maybe Float
parsuj tekst =
    String.toFloat (String.replace "," "." (String.trim tekst))


numerAuta : Kierowca -> Int
numerAuta k =
    Maybe.withDefault 0 (String.toInt k.id)


zaokr4 : Float -> String
zaokr4 x =
    String.fromFloat (toFloat (round (x * 10000)) / 10000)


opisBledu : Http.Error -> String
opisBledu blad =
    case blad of
        Http.BadStatus 401 ->
            "Nieprawidłowy e-mail lub hasło."

        Http.BadStatus 409 ->
            "Rejestracja nie powiodła się, spróbuj ponownie."

        Http.BadStatus 429 ->
            "Za dużo prób naraz. Odczekaj 10 sekund i spróbuj ponownie."

        Http.NetworkError ->
            "Brak połączenia z serwerem."

        _ ->
            "Coś poszło nie tak. Spróbuj ponownie."


opisBleduZamowienia : Http.Error -> String
opisBleduZamowienia blad =
    case blad of
        Http.BadStatus 400 ->
            "Niepoprawne zamówienie. Sprawdź współrzędne i liczbę miejsc."

        Http.BadStatus 409 ->
            "Masz już aktywny przejazd."

        Http.BadStatus 429 ->
            "Za dużo prób naraz. Zamówienie złożysz za 10 sekund."

        Http.NetworkError ->
            "Brak połączenia z serwerem."

        _ ->
            "Coś poszło nie tak. Spróbuj ponownie."


opisBleduOpinii : Http.Error -> String
opisBleduOpinii blad =
    case blad of
        Http.BadStatus 429 ->
            "Za dużo prób naraz. Opinię dodasz za 10 sekund."

        _ ->
            "Nie udało się dodać opinii. Spróbuj ponownie."



-- KLASY AUT
-- backend zna tylko liczbę wolnych miejsc, więc to ona wyznacza klasę i model 3D auta


type alias Klasa =
    { kod : String
    , nazwa : String
    , miejsca : Int
    , opis : String
    }


mini : Klasa
mini =
    Klasa "mini" "Mini" 2 "Mały biały hatchback na dwie osoby. Zmieści się w każdej uliczce Starego Miasta."


komfort : Klasa
komfort =
    Klasa "komfort" "Komfort" 3 "Granatowy sedan na trzy osoby. Spokojny kurs przez całe miasto."


kombi : Klasa
kombi =
    Klasa "kombi" "Kombi" 4 "Grafitowe kombi na cztery osoby i duży bagażnik."


xl : Klasa
xl =
    Klasa "xl" "XL" 5 "Jasny van z pięcioma miejscami, gdy jedzie was czworo z bagażami."


klasaAuta : Kierowca -> Klasa
klasaAuta k =
    if k.wolne <= 2 then
        mini

    else if k.wolne == 3 then
        komfort

    else if k.wolne == 4 then
        kombi

    else
        xl


{-| najmniejsza klasa, w której zmieści się tyle osób; bagaż podbija o jedną klasę
-}
klasaDla : Int -> Bool -> Klasa
klasaDla osoby bagaz =
    let
        podstawowa =
            if osoby <= 2 then
                0

            else
                osoby - 2

        poziom =
            if bagaz then
                podstawowa + 1

            else
                podstawowa
    in
    case poziom of
        0 ->
            mini

        1 ->
            komfort

        2 ->
            kombi

        _ ->
            xl


{-| "nas jest troje" -> 3 osoby, "czworo z walizkami" -> 4 osoby i bagaż
-}
parsujPytanie : String -> Maybe ( Int, Bool )
parsujPytanie tekst =
    let
        t =
            String.toLower tekst

        ma slowa =
            List.any (\s -> String.contains s t) slowa

        bagaz =
            ma [ "walizk", "bagaż", "bagaz", "rower", "narty", "plecak" ]

        osoby =
            if ma [ "5", "6", "7", "8", "pięć", "piec", "pięcio", "piecio", "sześć", "szesc" ] then
                Just 5

            else if ma [ "4", "czter", "czworo", "czwórk", "czwork" ] then
                Just 4

            else if ma [ "3", "trzy", "trzech", "troje", "trójk", "trojk" ] then
                Just 3

            else if ma [ "2", "dwa", "dwie", "dwoje", "dwóch", "dwoch", "para", "z żoną", "z mężem", "z kimś" ] then
                Just 2

            else if ma [ "1", "sam", "jeden", "jedna", "solo" ] then
                Just 1

            else
                Nothing
    in
    Maybe.map (\n -> ( n, bagaz )) osoby



-- MIEJSCA NA TAŚMIE W NAGŁÓWKU


type alias Miejsce =
    { nazwa : String
    , lat : Float
    , lon : Float
    , zdjecie : String
    , szer : Int
    , wys : Int
    , opis : String
    }


miejscaNaTasmie : List Miejsce
miejscaNaTasmie =
    [ Miejsce "Dworzec Główny" 51.0981 17.0365 "img/dworzec.jpg" 1920 1221 "Pusty peron pod stalowym dachem Dworca Głównego nocą"
    , Miejsce "Rynek" 51.11 17.032 "img/rynek.jpg" 1920 1162 "Dorożka z pasażerami na bruku wrocławskiego Rynku"
    , Miejsce "Most Młyński" 51.1155 17.042 "img/most-mlynski.jpg" 1920 1185 "Kratownice Mostu Młyńskiego we mgle przed świtem"
    , Miejsce "Muzeum Narodowe" 51.1104 17.047 "img/muzeum.jpg" 1920 1343 "Ceglany gmach Muzeum Narodowego odbity nocą w Odrze"
    ]


odlegloscKm : Float -> Float -> Float -> Float -> Float
odlegloscKm lat1 lon1 lat2 lon2 =
    let
        dy =
            (lat1 - lat2) * 111.2

        dx =
            (lon1 - lon2) * 111.2 * cos (degrees ((lat1 + lat2) / 2))
    in
    sqrt (dx * dx + dy * dy)


wolneAuta : List Kierowca -> List Kierowca
wolneAuta =
    List.filter (\k -> k.cel == Nothing)


wPoblizu : List Kierowca -> Miejsce -> String
wPoblizu flota m =
    let
        n =
            List.length (List.filter (\k -> odlegloscKm k.lat k.lon m.lat m.lon <= 2) (wolneAuta flota))
    in
    if List.isEmpty flota then
        "łączenie z flotą…"

    else if n == 0 then
        "brak wolnych aut w promieniu 2 km"

    else
        wolnychAut n ++ " w promieniu 2 km"



-- ODMIANA


kilka : Int -> Bool
kilka n =
    modBy 10 n >= 2 && modBy 10 n <= 4 && (modBy 100 n < 12 || modBy 100 n > 14)


aut : Int -> String
aut n =
    String.fromInt n
        ++ (if n == 1 then
                " auto"

            else if kilka n then
                " auta"

            else
                " aut"
           )


wolnychAut : Int -> String
wolnychAut n =
    String.fromInt n
        ++ (if n == 1 then
                " wolne auto"

            else if kilka n then
                " wolne auta"

            else
                " wolnych aut"
           )


miejsc : Int -> String
miejsc n =
    String.fromInt n
        ++ (if n == 1 then
                " miejsce"

            else if kilka n then
                " miejsca"

            else
                " miejsc"
           )


osob : Int -> String
osob n =
    String.fromInt n
        ++ (if n == 1 then
                " osoba"

            else if kilka n then
                " osoby"

            else
                " osób"
           )


jednoMiejsce : Float -> String
jednoMiejsce x =
    String.replace "." "," (String.fromFloat (toFloat (round (x * 10)) / 10))


stanFloty : List Kierowca -> String
stanFloty flota =
    if List.isEmpty flota then
        "Łączenie z flotą…"

    else
        aut (List.length flota) ++ " w mieście, wolne: " ++ String.fromInt (List.length (wolneAuta flota))



-- HTTP


zaloguj : String -> String -> Cmd Msg
zaloguj =
    wyslijPoswiadczenia "/login" OdpowiedzLogin


zarejestruj : String -> String -> Cmd Msg
zarejestruj =
    wyslijPoswiadczenia "/rejestracja" OdpowiedzRejestracja


{-| /login i /rejestracja przyjmują ten sam JSON i odpowiadają tym samym tokenem
-}
wyslijPoswiadczenia : String -> (Result Http.Error String -> Msg) -> String -> String -> Cmd Msg
wyslijPoswiadczenia url naOdpowiedz email haslo =
    Http.post
        { url = url
        , body =
            Http.jsonBody
                (E.object
                    [ ( "email", E.string email )
                    , ( "haslo", E.string haslo )
                    ]
                )
        , expect = Http.expectJson naOdpowiedz (D.field "token" D.string)
        }


pobierzJa : String -> Cmd Msg
pobierzJa token =
    Http.request
        { method = "GET"
        , headers = [ naglowekBearer token ]
        , url = "/ja"
        , body = Http.emptyBody
        , expect = Http.expectJson (OdpowiedzJa token) jaDekoder
        , timeout = Nothing
        , tracker = Nothing
        }


przywroc : String -> Cmd Msg
przywroc token =
    Http.request
        { method = "GET"
        , headers = [ naglowekBearer token ]
        , url = "/ja"
        , body = Http.emptyBody
        , expect = Http.expectJson (OdpowiedzPrzywrocenie token) jaDekoder
        , timeout = Nothing
        , tracker = Nothing
        }


{-| co 2 sekundy: czy przejazd nadal trwa; wersja pozwala odrzucić spóźnione odpowiedzi
-}
pobierzStan : String -> Int -> Cmd Msg
pobierzStan token wersja =
    Http.request
        { method = "GET"
        , headers = [ naglowekBearer token ]
        , url = "/ja"
        , body = Http.emptyBody
        , expect = Http.expectJson (OdpowiedzStanu wersja) jaDekoder
        , timeout = Nothing
        , tracker = Nothing
        }


jaDekoder : D.Decoder Ja
jaDekoder =
    D.map2 Ja
        (D.field "mojemail" D.string)
        (D.field "przejadz" (D.nullable D.string))


wylogujNaSerwerze : String -> Cmd Msg
wylogujNaSerwerze token =
    Http.request
        { method = "POST"
        , headers = [ naglowekBearer token ]
        , url = "/wyloguj"
        , body = Http.emptyBody
        , expect = Http.expectWhatever OdpowiedzWyloguj
        , timeout = Nothing
        , tracker = Nothing
        }


{-| lista aut jest publiczna, bez tokenu
-}
pobierzKierowcow : Cmd Msg
pobierzKierowcow =
    Http.get
        { url = "/kierowcy"
        , expect = Http.expectJson OdpowiedzKierowcy (D.list kierowcaDekoder)
        }


zamow : String -> Float -> Float -> Float -> Float -> Int -> Cmd Msg
zamow token startLat startLon celLat celLon ileMiejsc =
    Http.request
        { method = "POST"
        , headers = [ naglowekBearer token ]
        , url = "/zamowienie"
        , body =
            Http.jsonBody
                (E.object
                    [ ( "lat_startowy", E.float startLat )
                    , ( "lon_startowy", E.float startLon )
                    , ( "lat_koncowy", E.float celLat )
                    , ( "lon_koncowy", E.float celLon )
                    , ( "miejsca", E.int ileMiejsc )
                    ]
                )
        , expect = Http.expectJson OdpowiedzZamowienie kierowcaDekoder
        , timeout = Nothing
        , tracker = Nothing
        }


pobierzPrzejazdy : String -> Cmd Msg
pobierzPrzejazdy token =
    Http.request
        { method = "GET"
        , headers = [ naglowekBearer token ]
        , url = "/mojeprzejazdy"
        , body = Http.emptyBody
        , expect = Http.expectJson OdpowiedzPrzejazdy (D.list przejazdDekoder)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| mimo że to odczyt, backend chce POST z ciałem {"reqidkier": ...}
-}
pobierzKomentarze : String -> String -> Cmd Msg
pobierzKomentarze token id =
    Http.request
        { method = "POST"
        , headers = [ naglowekBearer token ]
        , url = "/komentarze"
        , body = Http.jsonBody (E.object [ ( "reqidkier", E.string id ) ])
        , expect = Http.expectJson (OdpowiedzKomentarze id) (D.list komentarzDekoder)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| backend wymaga w JSON-ie pól wystawiajacy i czasotrzymania, ale ignoruje je:
autora bierze z tokenu, a datę ustawia sam
-}
wystawKomentarz : String -> String -> Float -> String -> Cmd Msg
wystawKomentarz token id ocena tresc =
    Http.request
        { method = "POST"
        , headers = [ naglowekBearer token ]
        , url = "/wystawkomentarz"
        , body =
            Http.jsonBody
                (E.object
                    [ ( "idKier", E.string id )
                    , ( "wystawiajacy", E.string "" )
                    , ( "czasotrzymania", E.string "" )
                    , ( "ocena", E.float ocena )
                    , ( "tresc", E.string tresc )
                    ]
                )
        , expect = Http.expectWhatever OdpowiedzWystawienia
        , timeout = Nothing
        , tracker = Nothing
        }


kierowcaDekoder : D.Decoder Kierowca
kierowcaDekoder =
    let
        para =
            D.nullable (D.map2 Tuple.pair (D.index 0 D.float) (D.index 1 D.float))
    in
    D.map6 Kierowca
        (D.field "idKierowcy" D.string)
        (D.field "lat" D.float)
        (D.field "lon" D.float)
        (D.field "cel" para)
        (D.field "celKoncowy" para)
        (D.field "wolne_miejsca" D.int)


przejazdDekoder : D.Decoder Przejazd
przejazdDekoder =
    D.map7 Przejazd
        (D.field "vehicle_id" (D.map String.fromInt D.int))
        (D.field "pickup_lat" D.float)
        (D.field "pickup_lng" D.float)
        (D.field "dropoff_lat" D.float)
        (D.field "dropoff_lng" D.float)
        (D.field "status" D.string)
        (D.field "created_at" D.string)


komentarzDekoder : D.Decoder Komentarz
komentarzDekoder =
    D.map4 Komentarz
        (D.field "wystawiajacy" D.string)
        (D.field "czasotrzymania" D.string)
        (D.field "ocena" D.float)
        (D.field "tresc" D.string)


{-| backend (wszystko poza /login i /rejestracja) wymaga prefiksu "Bearer "
-}
naglowekBearer : String -> Http.Header
naglowekBearer token =
    Http.header "Authorization" ("Bearer " ++ token)



-- 3D
-- <unter-auto> i <unter-miasto> to custom elementy z public/unter3d.js (Three.js);
-- dane dostają w atrybutach jako JSON, kliknięcia oddają zdarzeniami


flotaJson : List Kierowca -> String
flotaJson flota =
    E.encode 0
        (E.list
            (\k ->
                E.object
                    [ ( "id", E.string k.id )
                    , ( "lat", E.float k.lat )
                    , ( "lon", E.float k.lon )
                    , ( "wolne", E.int k.wolne )
                    , ( "cel", punktJson k.cel )
                    , ( "celKoncowy", punktJson k.celKoncowy )
                    ]
            )
            flota
        )


punktJson : Maybe ( Float, Float ) -> E.Value
punktJson punkt =
    case punkt of
        Just ( la, lo ) ->
            E.list E.float [ la, lo ]

        Nothing ->
            E.null


punktyJson : List Znacznik -> String
punktyJson punkty =
    E.encode 0
        (E.list
            (\z ->
                E.object
                    [ ( "rodzaj", E.string z.klasa )
                    , ( "lat", E.float z.lat )
                    , ( "lon", E.float z.lon )
                    ]
            )
            punkty
        )


auto3d : String -> Klasa -> Bool -> Html Msg
auto3d klasaCss k wolne =
    node "unter-auto"
        [ class klasaCss
        , attribute "model" k.kod
        , attribute "wolne"
            (if wolne then
                "tak"

             else
                "nie"
            )
        , attribute "role" "img"
        , attribute "aria-label" ("Model 3D auta klasy " ++ k.nazwa ++ ". Przeciągnij, aby obrócić.")
        ]
        []



-- VIEW


view : Model -> Html Msg
view model =
    case model.stan of
        Zalogowany sesja ->
            widokAplikacji model.flota sesja

        _ ->
            stronaGlowna model


wejscie : Int -> List (Html.Attribute Msg)
wejscie krok =
    [ attribute "data-wejdz" "", attribute "data-krok" (String.fromInt krok) ]



-- strona główna


stronaGlowna : Model -> Html Msg
stronaGlowna model =
    div [ class "strona" ]
        [ hero model.flota
        , sekcjaFlota model
        , sekcjaJak
        , sekcjaPytania
        , sekcjaKonto model
        , stopka
        ]


hero : List Kierowca -> Html Msg
hero flota =
    section [ id "hero", class "hero" ]
        [ div [ class "hero__scena" ]
            [ header [ class "pasek" ]
                [ a [ class "znak", href "#hero" ] [ text "unter" ]
                , nav [ class "pasek__linki", attribute "aria-label" "Strona główna" ]
                    [ a [ class "pasek__link", href "#flota" ] [ text "Flota" ]
                    , a [ class "pasek__link", href "#jak" ] [ text "Jak to działa" ]
                    , a [ class "pasek__link", href "#pytania" ] [ text "Pytania" ]
                    , a [ class "pasek__link", href repozytorium ] [ text "GitHub" ]
                    , a [ class "przycisk przycisk--maly", href "#konto" ] [ text "Zaloguj się" ]
                    ]
                ]
            , h1 [ class "hero__zdanie" ]
                [ span [ class "pol pol--lewa" ] [ text "Przejazdy" ]
                , text " "
                , span [ class "pol pol--prawa" ] [ text "po Wrocławiu" ]
                ]
            , div [ class "tasma" ]
                (figure [ class "kadr kadr--miasto" ]
                    [ node "unter-miasto"
                        [ class "kadr__miasto"
                        , attribute "tryb" "podglad"
                        , attribute "auta" (flotaJson flota)
                        , attribute "role" "img"
                        , attribute "aria-label" "Mapa 3D Wrocławia z autami Unter w ich obecnych pozycjach"
                        ]
                        []
                    , figcaption [ class "kadr__podpis" ] [ text "Flota Unter na żywo" ]
                    ]
                    :: List.map (kadrMiejsca flota) miejscaNaTasmie
                )
            , div [ class "hero__opis" ]
                [ p [ class "hero__zdanie-pomocnicze" ]
                    [ text "Wskazujesz start i cel na mapie, a Unter wysyła najbliższe wolne auto, w którym zmieścicie się wszyscy." ]
                , div [ class "hero__akcja" ]
                    [ a [ class "przycisk", href "#konto" ] [ text "Zamów przejazd" ]
                    , p [ class "hero__na-zywo", attribute "aria-live" "polite" ] [ text (stanFloty flota) ]
                    ]
                ]
            ]
        ]


kadrMiejsca : List Kierowca -> Miejsce -> Html Msg
kadrMiejsca flota m =
    figure [ class "kadr" ]
        [ img [ src m.zdjecie, alt m.opis, width m.szer, height m.wys, attribute "decoding" "async" ] []
        , figcaption [ class "kadr__podpis" ] [ text (m.nazwa ++ " · " ++ wPoblizu flota m) ]
        ]


sekcjaFlota : Model -> Html Msg
sekcjaFlota model =
    let
        wynik =
            parsujPytanie model.pytanie

        ( osoby, klasa ) =
            case wynik of
                Just ( n, bagaz ) ->
                    ( n, klasaDla (min n 4) bagaz )

                Nothing ->
                    ( 3, komfort )

        pasujace =
            List.filter (\k -> k.wolne >= max (min osoby 4) klasa.miejsca) (wolneAuta model.flota)

        rynek =
            { lat = 51.11, lon = 17.032 }

        najblizsze =
            pasujace
                |> List.map (\k -> ( k, odlegloscKm k.lat k.lon rynek.lat rynek.lon ))
                |> List.sortBy Tuple.second
                |> List.head

        uwaga =
            case wynik of
                Nothing ->
                    Just "Napisz, ile osób jedzie, na przykład „we dwoje”. Na razie pokazujemy Komfort."

                Just ( n, _ ) ->
                    if n > 4 then
                        Just "Jedno zamówienie to najwyżej 4 osoby. Przy większej grupie zamówcie dwa auta."

                    else
                        Nothing
    in
    section [ id "flota", class "sekcja flota" ]
        [ h2 (id "flota-tytul" :: class "flota__tytul" :: wejscie 0) [ text "Ile was jedzie?" ]
        , input
            ([ id "pytanie"
             , class "flota__pole"
             , attribute "data-ui" ""
             , attribute "aria-labelledby" "flota-tytul"
             , type_ "text"
             , value model.pytanie
             , onInput WpisanoPytanie
             , spellcheck False
             , autocomplete False
             , maxlength 60
             ]
                ++ wejscie 1
            )
            []
        , div [ class "flota__uklad" ]
            [ div (class "flota__lewa" :: wejscie 2)
                [ div [ class "odpowiedz", attribute "data-ui" "", attribute "aria-live" "polite" ]
                    [ h3 [ class "odpowiedz__klasa" ] [ text klasa.nazwa ]
                    , p [ class "odpowiedz__opis" ] [ text klasa.opis ]
                    , dl [ class "dane" ]
                        [ div [ class "dane__wiersz" ]
                            [ dt [] [ text "Jedzie" ]
                            , dd [] [ text (osob osoby) ]
                            ]
                        , div [ class "dane__wiersz" ]
                            [ dt [] [ text "Wolne miejsca w aucie" ]
                            , dd [] [ text (String.fromInt klasa.miejsca) ]
                            ]
                        , div [ class "dane__wiersz" ]
                            [ dt [] [ text "Pasujących wolnych aut teraz" ]
                            , dd []
                                [ text
                                    (if List.isEmpty model.flota then
                                        "…"

                                     else
                                        String.fromInt (List.length pasujace)
                                    )
                                ]
                            ]
                        , div [ class "dane__wiersz" ]
                            [ dt [] [ text "Najbliżej Rynku" ]
                            , dd []
                                [ text
                                    (case najblizsze of
                                        Just ( k, km ) ->
                                            "#" ++ k.id ++ " · " ++ jednoMiejsce km ++ " km"

                                        Nothing ->
                                            "brak"
                                    )
                                ]
                            ]
                        ]
                    , case uwaga of
                        Just tresc ->
                            p [ class "odpowiedz__uwaga" ] [ text tresc ]

                        Nothing ->
                            text ""
                    ]
                , div [ class "przyklady" ]
                    (List.map
                        (\t -> button [ type_ "button", class "przyklad", onClick (WpisanoPytanie t) ] [ text t ])
                        [ "jadę sam", "we dwoje", "nas jest troje", "czworo z walizkami" ]
                    )
                ]
            , div (class "flota__scena" :: wejscie 3)
                [ auto3d "flota__auto" klasa True ]
            ]
        ]


type alias Etap =
    { czas : String
    , opis : String
    , waga : Int
    , kolor : String
    }


sekcjaJak : Html Msg
sekcjaJak =
    section [ id "jak", class "sekcja jak" ]
        [ h2 (class "jak__tytul" :: wejscie 0) [ text "Od kliknięcia do celu" ]
        , div (class "pasmo" :: attribute "data-ui" "" :: wejscie 1)
            (List.map etap
                [ Etap "Kilka sekund" "Najpierw wskazujesz na mapie start i cel, i liczbę osób." 6 "granat"
                , Etap "Od razu" "Potem Unter wybiera najbliższe wolne auto z miejscem dla was." 1 "czern"
                , Etap "Kilkanaście sekund" "Wtedy auto podjeżdża po was i wiezie do celu, a mapa pokazuje je co 2 sekundy." 20 "popiel"
                , Etap "Około minuty" "Na koniec, po dojechaniu, oceniasz kierowcę od 1 do 5 gwiazdek." 24 "kamien"
                ]
            )
        ]


etap : Etap -> Html Msg
etap e =
    div [ class "etap", style "flex-grow" (String.fromInt e.waga) ]
        [ div [ class ("etap__pole etap__pole--" ++ e.kolor) ] [ p [ class "etap__czas" ] [ text e.czas ] ]
        , p [ class "etap__opis" ] [ text e.opis ]
        ]


sekcjaPytania : Html Msg
sekcjaPytania =
    section [ id "pytania", class "sekcja pytania" ]
        [ h2 (class "pytania__tytul" :: wejscie 0) [ text "Zanim zamówisz" ]
        , ul (class "pytania__lista" :: wejscie 1)
            (List.map wierszPytania
                [ ( "Ile osób zmieści jedno zamówienie?", "Od jednej do czterech. Unter bierze pod uwagę tylko auta, które mają tyle wolnych miejsc." )
                , ( "Jak Unter wybiera auto?", "Spośród wolnych aut z wystarczającą liczbą miejsc wysyła to, które stoi najbliżej punktu startu." )
                , ( "Czy mogę zamówić dwa przejazdy naraz?", "Nie. Trwający przejazd widać w aplikacji na każdej zakładce, a kolejny zamówisz, gdy ten się zakończy." )
                , ( "Dlaczego czasem muszę chwilę poczekać?", "Logowanie, rejestracja, zamówienie i opinia mają wspólny limit kilku prób na 10 sekund z jednego adresu. To ochrona przed spamem." )
                , ( "Kto widzi moją opinię?", "Wszyscy zalogowani. Zamiast całego adresu e-mail pokazujemy tylko jego pierwszą literę i domenę." )
                , ( "Kiedy mogę ocenić kierowcę?", "Po zakończonym przejeździe. Aplikacja sama zaproponuje opinię, gdy auto dowiezie was do celu." )
                ]
            )
        ]


wierszPytania : ( String, String ) -> Html Msg
wierszPytania ( q, odp ) =
    li [ class "pytanie" ]
        [ details []
            [ summary [ class "pytanie__tresc" ] [ text q ]
            , p [ class "pytanie__odpowiedz" ] [ text odp ]
            ]
        ]


sekcjaKonto : Model -> Html Msg
sekcjaKonto model =
    section [ id "konto", class "sekcja konto" ]
        [ div [ class "konto__tekst" ]
            [ h2 (class "konto__tytul" :: wejscie 0) [ text "Jedno konto, cały Wrocław" ]
            , p (class "konto__opis" :: wejscie 1)
                [ text "Wystarczy e-mail i hasło. Po zalogowaniu widzisz całą flotę na mapie 3D, zamawiasz przejazd jednym kliknięciem i oceniasz kierowców." ]
            ]
        , div (class "konto__panel" :: attribute "data-ui" "" :: wejscie 2) (panelKonta model)
        ]


panelKonta : Model -> List (Html Msg)
panelKonta model =
    let
        rejestracja =
            model.tryb == Rejestracja

        wysylanie =
            model.stan == Wysylanie

        napis logowanie rejestr =
            if rejestracja then
                rejestr

            else
                logowanie
    in
    [ div [ class "segment", attribute "role" "group", attribute "aria-label" "Rodzaj formularza" ]
        [ przyciskSegmentu (not rejestracja) (UstawTryb Logowanie) "Logowanie"
        , przyciskSegmentu rejestracja (UstawTryb Rejestracja) "Rejestracja"
        ]
    , case model.stan of
        Sprawdzanie ->
            p [ class "komunikat" ] [ text "Sprawdzanie zapamiętanej sesji…" ]

        Wylogowany ->
            p [ class "komunikat komunikat--ok" ] [ text "Wylogowano. Do zobaczenia na trasie." ]

        _ ->
            text ""
    , form [ class "formularz", onSubmit (napis Zaloguj Zarejestruj) ]
        ([ label [ for "email" ] [ text "E-mail" ]
         , input
            [ id "email"
            , type_ "email"
            , autocomplete True
            , attribute "autocomplete" "email"
            , required True
            , value model.email
            , onInput WpisanoEmail
            ]
            []
         , label [ for "haslo" ] [ text "Hasło" ]
         , input
            [ id "haslo"
            , type_ "password"
            , attribute "autocomplete" (napis "current-password" "new-password")
            , required True
            , value model.haslo
            , onInput WpisanoHaslo
            ]
            []
         ]
            ++ (if rejestracja then
                    [ label [ for "powtorz" ] [ text "Powtórz hasło" ]
                    , input
                        [ id "powtorz"
                        , type_ "password"
                        , attribute "autocomplete" "new-password"
                        , required True
                        , value model.powtorz
                        , onInput WpisanoPowtorz
                        ]
                        []
                    ]

                else
                    []
               )
            ++ [ case model.stan of
                    Formularz (Just tresc) ->
                        p [ class "blad", attribute "role" "alert" ] [ text tresc ]

                    _ ->
                        text ""
               , button [ type_ "submit", class "przycisk przycisk--pelny", disabled wysylanie ]
                    [ text
                        (if wysylanie then
                            napis "Logowanie…" "Rejestrowanie…"

                         else
                            napis "Zaloguj się" "Załóż konto"
                        )
                    ]
               ]
        )
    ]


przyciskSegmentu : Bool -> Msg -> String -> Html Msg
przyciskSegmentu aktywny msg napis =
    button
        [ type_ "button"
        , classList [ ( "segment__opcja", True ), ( "segment__opcja--aktywna", aktywny ) ]
        , attribute "aria-pressed"
            (if aktywny then
                "true"

             else
                "false"
            )
        , onClick msg
        ]
        [ text napis ]


{-| kod projektu, linkowany w pasku i w stopce strony głównej
-}
repozytorium : String
repozytorium =
    "https://github.com/dhmztr/labybespapkweb"


stopka : Html Msg
stopka =
    footer [ class "stopka" ]
        [ div [ class "stopka__gora" ]
            [ div [ class "stopka__zaproszenie" ]
                [ h2 [ class "stopka__tytul" ] [ text "Gdzie dziś jedziesz?" ]
                , a [ class "przycisk", href "#konto" ] [ text "Zamów przejazd" ]
                ]
            , ul [ class "stopka__linki" ]
                [ li [] [ a [ href "#flota" ] [ text "Flota" ] ]
                , li [] [ a [ href "#jak" ] [ text "Jak to działa" ] ]
                , li [] [ a [ href "#pytania" ] [ text "Pytania" ] ]
                , li [] [ a [ href "/swagger-ui" ] [ text "Dokumentacja API" ] ]
                , li [] [ a [ href repozytorium ] [ text "Kod na GitHubie" ] ]
                ]
            ]
        , div [ class "stopka__dol" ]
            [ p [ class "stopka__zrodla" ]
                [ text "Zdjęcia: "
                , zrodlo "https://commons.wikimedia.org/wiki/File:Breslau-People-16-Rynek-Droschke-2014-gje.jpg" "Rynek" "Gerd Eichmann" "https://creativecommons.org/licenses/by/4.0" "CC BY 4.0"
                , text "; "
                , zrodlo "https://commons.wikimedia.org/wiki/File:Wroclaw_Most_Mlynski_w_porannej_mgle_przed_switem.jpg" "Most Młyński" "Jar.ciurus" "https://creativecommons.org/licenses/by-sa/3.0/pl/deed.en" "CC BY-SA 3.0"
                , text "; "
                , zrodlo "https://commons.wikimedia.org/wiki/File:Wroc%C5%82aw_G%C5%82%C3%B3wny_(Breslau_Hauptbahnhof)_by_night.JPG" "Dworzec Główny" "Pudelek (Marcin Szala)" "https://creativecommons.org/licenses/by-sa/4.0" "CC BY-SA 4.0"
                , text "; "
                , zrodlo "https://commons.wikimedia.org/wiki/File:Wroc%C5%82aw_MuzeumNarodowe.jpg" "Muzeum Narodowe" "Marek Śliwecki" "https://creativecommons.org/licenses/by-sa/4.0" "CC BY-SA 4.0"
                , text "; wszystkie przez Wikimedia Commons. Mapa: Esri, HERE, Garmin, © "
                , a [ href "https://www.openstreetmap.org/copyright" ] [ text "OpenStreetMap" ]
                , text "."
                ]
            , p [ class "stopka__projekt" ] [ text "Unter, projekt studencki · Wrocław 2026" ]
            ]
        , p [ class "stopka__nazwa", attribute "aria-hidden" "true" ] [ text "unter" ]
        ]


zrodlo : String -> String -> String -> String -> String -> Html Msg
zrodlo strona nazwa autor licencjaUrl licencja =
    span []
        [ a [ href strona ] [ text nazwa ]
        , text (", " ++ autor ++ ", ")
        , a [ href licencjaUrl ] [ text licencja ]
        ]



-- aplikacja po zalogowaniu


widokAplikacji : List Kierowca -> Sesja -> Html Msg
widokAplikacji flota s =
    div [ class "app" ]
        [ header [ class "app__pasek" ]
            [ span [ class "znak znak--app" ] [ text "unter" ]
            , nav [ class "app__zakladki", attribute "aria-label" "Aplikacja" ]
                [ zakladka s StronaAuta "Auta"
                , zakladka s StronaZamowienie "Zamów"
                , zakladka s StronaPrzejazdy "Przejazdy"
                , zakladka s StronaKomentarze "Opinie"
                ]
            , div [ class "app__konto" ]
                [ span [ class "app__email" ] [ text s.email ]
                , button [ type_ "button", class "przycisk-tekst", onClick Wyloguj ] [ text "Wyloguj" ]
                ]
            ]
        , div [ class "app__cialo" ]
            [ main_ [ class "panel" ]
                (komunikatyPrzejazdu flota s
                    ++ (case s.strona of
                            StronaAuta ->
                                widokAut flota s

                            StronaZamowienie ->
                                widokZamowienia flota s

                            StronaPrzejazdy ->
                                widokPrzejazdow s

                            StronaKomentarze ->
                                widokOpinii flota s
                       )
                )
            , mapa3d flota s
            ]
        ]


{-| aktywny przejazd widać na każdej zakładce; po dojechaniu pojawia się zaproszenie do oceny
-}
komunikatyPrzejazdu : List Kierowca -> Sesja -> List (Html Msg)
komunikatyPrzejazdu flota s =
    let
        koniec =
            case s.zakonczony of
                Just id ->
                    if s.strona == StronaKomentarze && s.kom.wybrany == Just id then
                        []

                    else
                        [ div [ class "baner baner--koniec", attribute "role" "status" ]
                            [ p [ class "baner__tekst" ] [ text ("Przejazd autem #" ++ id ++ " zakończony. Jak było?") ]
                            , div [ class "baner__akcje" ]
                                [ button [ type_ "button", class "przycisk przycisk--maly", onClick (OtworzOpinie id) ] [ text "Oceń kierowcę" ]
                                , button [ type_ "button", class "przycisk-tekst", onClick ZamknijKomunikat ] [ text "Później" ]
                                ]
                            ]
                        ]

                Nothing ->
                    []

        trwa =
            case s.przejazd of
                Just id ->
                    if s.strona == StronaZamowienie then
                        []

                    else
                        [ div [ class "baner", attribute "role" "status" ]
                            [ p [ class "baner__tekst" ] [ text (opisPrzejazdu flota id) ]
                            , button [ type_ "button", class "przycisk-tekst", onClick (IdzDo StronaZamowienie) ] [ text "Pokaż" ]
                            ]
                        ]

                Nothing ->
                    []
    in
    koniec ++ trwa


opisPrzejazdu : List Kierowca -> String -> String
opisPrzejazdu flota id =
    case znajdzAuto flota id of
        Just k ->
            case etapAuta k of
                PoKlienta ( la, lo ) _ ->
                    "Auto #" ++ id ++ " jedzie po Ciebie, jest " ++ jednoMiejsce (odlegloscKm k.lat k.lon la lo) ++ " km od miejsca odbioru."

                DoCelu ( la, lo ) ->
                    "Jedziesz autem #" ++ id ++ ". Do celu zostało " ++ jednoMiejsce (odlegloscKm k.lat k.lon la lo) ++ " km."

                Wolne ->
                    "Auto #" ++ id ++ " właśnie dojeżdża na miejsce."

        Nothing ->
            "Twój przejazd autem #" ++ id ++ " trwa."


zakladka : Sesja -> Strona -> String -> Html Msg
zakladka s strona napis =
    button
        [ type_ "button"
        , classList [ ( "zakladka", True ), ( "zakladka--aktywna", s.strona == strona ) ]
        , attribute "aria-current"
            (if s.strona == strona then
                "page"

             else
                "false"
            )
        , onClick (IdzDo strona)
        ]
        [ text napis ]


{-| jedna mapa na wszystkie zakładki: stoi zawsze w tym samym miejscu drzewa,
więc Elm jej nie podmienia i WebGL nie startuje od nowa przy każdym kliknięciu
-}
mapa3d : List Kierowca -> Sesja -> Html Msg
mapa3d flota s =
    let
        punkty =
            if s.strona /= StronaZamowienie then
                []

            else
                case ( s.przejazd, Maybe.andThen (znajdzAuto flota) s.przejazd ) of
                    ( Just _, Just k ) ->
                        punktyPrzejazdu s.zam k

                    ( Just _, Nothing ) ->
                        []

                    ( Nothing, _ ) ->
                        punktyZamowienia s.zam

        klikalna =
            s.strona == StronaZamowienie && s.przejazd == Nothing

        wybrane =
            case s.strona of
                StronaAuta ->
                    s.wybrane

                StronaZamowienie ->
                    s.przejazd

                StronaPrzejazdy ->
                    s.wybrane

                StronaKomentarze ->
                    s.kom.wybrany
    in
    node "unter-miasto"
        [ class "app__mapa"
        , attribute "tryb" "aplikacja"
        , attribute "auta" (flotaJson flota)
        , attribute "punkty" (punktyJson punkty)
        , attribute "wybrane" (Maybe.withDefault "" wybrane)
        , attribute "klikalna"
            (if klikalna then
                "tak"

             else
                "nie"
            )
        , attribute "aria-label" "Mapa 3D Wrocławia z autami Unter"
        , on "wybierz-auto" (D.map WybranoAuto (D.at [ "detail", "id" ] D.string))
        , on "klik-mapa" (D.map2 KlikMapa (D.at [ "detail", "lat" ] D.float) (D.at [ "detail", "lon" ] D.float))
        ]
        [ mapa klikalna flota punkty ]


{-| pinezki trwającego przejazdu: dopóki auto jedzie po klienta, oba punkty są w danych auta;
potem zostaje tylko cel, a start bierzemy z formularza (jeśli zamówienie złożono w tej sesji)
-}
punktyPrzejazdu : FormZamowienia -> Kierowca -> List Znacznik
punktyPrzejazdu z k =
    case etapAuta k of
        PoKlienta ( la, lo ) ( ca, co ) ->
            [ Znacznik "start" la lo "S", Znacznik "cel" ca co "C" ]

        DoCelu ( ca, co ) ->
            List.filter (\p -> p.klasa == "start") (punktyZamowienia z) ++ [ Znacznik "cel" ca co "C" ]

        Wolne ->
            punktyZamowienia z


znajdzAuto : List Kierowca -> String -> Maybe Kierowca
znajdzAuto flota id =
    List.head (List.filter (\k -> k.id == id) flota)


statusAuta : Kierowca -> String
statusAuta k =
    case etapAuta k of
        Wolne ->
            "wolne"

        PoKlienta _ _ ->
            "po klienta"

        DoCelu _ ->
            "w trasie"


statusKlasa : Kierowca -> String
statusKlasa k =
    "plakietka plakietka--" ++ String.replace " " "-" (statusAuta k)


-- auta


widokAut : List Kierowca -> Sesja -> List (Html Msg)
widokAut flota s =
    [ h1 [ class "panel__tytul" ] [ text "Auta w mieście" ]
    , p [ class "panel__opis" ]
        [ text
            (if List.isEmpty flota then
                "Łączenie z flotą…"

             else
                aut (List.length flota) ++ ", wolne: " ++ String.fromInt (List.length (wolneAuta flota)) ++ ". Pozycje odświeżają się co 2 sekundy."
            )
        ]
    , case Maybe.andThen (znajdzAuto flota) s.wybrane of
        Just k ->
            kartaAuta k
                [ button [ type_ "button", class "przycisk przycisk--ciemny", onClick (OtworzOpinie k.id) ] [ text "Opinie o aucie" ]
                , button [ type_ "button", class "przycisk-drugi", onClick (IdzDo StronaZamowienie) ] [ text "Zamów przejazd" ]
                ]

        Nothing ->
            p [ class "podpowiedz" ] [ text "Wybierz auto z listy albo kliknij je na mapie." ]
    , if List.isEmpty flota then
        p [ class "pusto" ] [ text "Brak aut do wyświetlenia." ]

      else
        ul [ class "lista-aut" ] (List.map (wierszAuta s.wybrane) flota)
    ]


kartaAuta : Kierowca -> List (Html Msg) -> Html Msg
kartaAuta k przyciski =
    let
        kl =
            klasaAuta k
    in
    div [ class "karta-auta" ]
        [ auto3d "karta-auta__model" kl (k.cel == Nothing)
        , h2 [ class "karta-auta__tytul" ] [ text ("#" ++ k.id ++ " · " ++ kl.nazwa) ]
        , dl [ class "dane dane--kompakt" ]
            [ div [ class "dane__wiersz" ] [ dt [] [ text "Status" ], dd [] [ span [ class (statusKlasa k) ] [ text (statusAuta k) ] ] ]
            , div [ class "dane__wiersz" ] [ dt [] [ text "Wolne miejsca" ], dd [] [ text (String.fromInt k.wolne) ] ]
            , div [ class "dane__wiersz" ] [ dt [] [ text "Pozycja" ], dd [] [ text (zaokr4 k.lat ++ ", " ++ zaokr4 k.lon) ] ]
            ]
        , if List.isEmpty przyciski then
            text ""

          else
            div [ class "przyciski" ] przyciski
        ]


wierszAuta : Maybe String -> Kierowca -> Html Msg
wierszAuta wybrane k =
    let
        kl =
            klasaAuta k

        aktywny =
            wybrane == Just k.id
    in
    li []
        [ button
            [ type_ "button"
            , classList [ ( "wiersz", True ), ( "wiersz--wybrany", aktywny ) ]
            , attribute "aria-pressed"
                (if aktywny then
                    "true"

                 else
                    "false"
                )
            , onClick (WybranoAuto k.id)
            ]
            [ span [ class "wiersz__nr" ] [ text ("#" ++ k.id) ]
            , span [ class "wiersz__klasa" ] [ text kl.nazwa ]
            , span [ class (statusKlasa k) ] [ text (statusAuta k) ]
            , span [ class "wiersz__miejsca" ] [ text (miejsc k.wolne) ]
            ]
        ]



-- mapa 2D: zapasowa, gdy przeglądarka nie ma WebGL


{-| zakres współrzędnych widoczny na mapie
-}
type alias Granice =
    { latMin : Float
    , latMax : Float
    , lonMin : Float
    , lonMax : Float
    }


{-| domyślnie okolice Wrocławia, ale auta błądzą losowo i z czasem odpływają,
więc zakres rozszerzamy tak, żeby zawsze mieściły się wszystkie auta i punkty
(zaokrąglony do 0,05°, żeby mapa nie "pływała" przy każdym ruchu auta)
-}
granice : List Kierowca -> List Znacznik -> Granice
granice kierowcy punkty =
    let
        szerokosci =
            51.0 :: 51.2 :: (List.map .lat kierowcy ++ List.map .lat punkty)

        dlugosci =
            16.85 :: 17.15 :: (List.map .lon kierowcy ++ List.map .lon punkty)

        dol x =
            toFloat (floor (x / 0.05)) * 0.05

        gora x =
            toFloat (ceiling (x / 0.05)) * 0.05
    in
    { latMin = dol (Maybe.withDefault 51.0 (List.minimum szerokosci))
    , latMax = gora (Maybe.withDefault 51.2 (List.maximum szerokosci))
    , lonMin = dol (Maybe.withDefault 16.85 (List.minimum dlugosci))
    , lonMax = gora (Maybe.withDefault 17.15 (List.maximum dlugosci))
    }


{-| punkty start i cel z formularza zamówienia
-}
type alias Znacznik =
    { klasa : String
    , lat : Float
    , lon : Float
    , napis : String
    }


mapa : Bool -> List Kierowca -> List Znacznik -> Html Msg
mapa klikalna kierowcy punkty =
    let
        g =
            granice kierowcy punkty
    in
    div
        (class
            (if klikalna then
                "mapa klikalna"

             else
                "mapa"
            )
            :: (if klikalna then
                    [ on "click" (klikDekoder g) ]

                else
                    []
               )
        )
        (List.map (znacznikAuta g) kierowcy ++ List.map (znacznikPunktu g) punkty)


{-| pozycja kliknięcia w pikselach zamieniamy na współrzędne geograficzne;
znaczniki mają pointer-events: none, więc target to zawsze sama mapa
-}
klikDekoder : Granice -> D.Decoder Msg
klikDekoder g =
    D.map4
        (\x y szer wys ->
            KlikMapa
                (g.latMax - y / wys * (g.latMax - g.latMin))
                (g.lonMin + x / szer * (g.lonMax - g.lonMin))
        )
        (D.field "offsetX" D.float)
        (D.field "offsetY" D.float)
        (D.at [ "target", "offsetWidth" ] D.float)
        (D.at [ "target", "offsetHeight" ] D.float)


pozycja : Granice -> Float -> Float -> List (Html.Attribute Msg)
pozycja g lat lon =
    [ style "left" (procent ((lon - g.lonMin) / (g.lonMax - g.lonMin)))
    , style "top" (procent ((g.latMax - lat) / (g.latMax - g.latMin)))
    ]


procent : Float -> String
procent u =
    String.fromFloat (clamp 0 100 (u * 100)) ++ "%"


znacznikAuta : Granice -> Kierowca -> Html Msg
znacznikAuta g k =
    div
        (classList [ ( "auto", True ), ( "zajete", k.cel /= Nothing ) ]
            :: title ("Auto #" ++ k.id)
            :: pozycja g k.lat k.lon
        )
        [ text k.id ]


znacznikPunktu : Granice -> Znacznik -> Html Msg
znacznikPunktu g z =
    div (class ("punkt " ++ z.klasa) :: pozycja g z.lat z.lon) [ text z.napis ]



-- zamówienie


widokZamowienia : List Kierowca -> Sesja -> List (Html Msg)
widokZamowienia flota s =
    case s.przejazd of
        Just id ->
            widokPrzejazdu flota id

        Nothing ->
            formularzZamowienia flota s.zam


widokPrzejazdu : List Kierowca -> String -> List (Html Msg)
widokPrzejazdu flota id =
    case znajdzAuto flota id of
        Nothing ->
            [ h1 [ class "panel__tytul" ] [ text "Twój przejazd" ]
            , p [ class "panel__opis" ] [ text ("Szukamy auta #" ++ id ++ " na mapie…") ]
            ]

        Just k ->
            let
                biezacy =
                    etapAuta k

                ( tytul, opis ) =
                    case biezacy of
                        PoKlienta ( la, lo ) _ ->
                            ( "Auto #" ++ id ++ " jedzie po Ciebie"
                            , "Do miejsca odbioru zostało " ++ jednoMiejsce (odlegloscKm k.lat k.lon la lo) ++ " km. Czekaj przy pinezce Start."
                            )

                        DoCelu ( la, lo ) ->
                            ( "Jesteś w drodze"
                            , "Do celu zostało " ++ jednoMiejsce (odlegloscKm k.lat k.lon la lo) ++ " km."
                            )

                        Wolne ->
                            ( "Jesteś na miejscu", "Za chwilę zamkniemy przejazd i poprosimy o opinię." )
            in
            [ h1 [ class "panel__tytul" ] [ text tytul ]
            , p [ class "panel__opis", attribute "aria-live" "polite" ] [ text opis ]
            , etapyPrzejazdu biezacy
            , kartaAuta k []
            , p [ class "podpowiedz" ] [ text "Kolejny przejazd zamówisz, gdy ten się zakończy. Wtedy też ocenisz kierowcę." ]
            ]


etapyPrzejazdu : EtapKursu -> Html Msg
etapyPrzejazdu biezacy =
    let
        teraz =
            case biezacy of
                PoKlienta _ _ ->
                    0

                DoCelu _ ->
                    1

                Wolne ->
                    2

        krokPrzejazdu i napis =
            li
                [ classList [ ( "kroki__krok", True ), ( "kroki__krok--zrobiony", i < teraz ), ( "kroki__krok--teraz", i == teraz ) ]
                , attribute "aria-current"
                    (if i == teraz then
                        "step"

                     else
                        "false"
                    )
                ]
                [ text napis ]
    in
    ul [ class "kroki", attribute "aria-label" "Etapy przejazdu" ]
        [ krokPrzejazdu 0 "Dojazd po Ciebie"
        , krokPrzejazdu 1 "W drodze do celu"
        , krokPrzejazdu 2 "Na miejscu"
        ]


formularzZamowienia : List Kierowca -> FormZamowienia -> List (Html Msg)
formularzZamowienia flota z =
    let
        wysylanie =
            z.stan == ZamWysylanie

        ile =
            Maybe.withDefault 1 (String.toInt z.miejsca)

        pasujace =
            List.filter (\k -> k.wolne >= ile) (wolneAuta flota)

        klasy =
            List.filter (\kl -> kl.miejsca >= ile) [ mini, komfort, kombi, xl ]
    in
    [ h1 [ class "panel__tytul" ] [ text "Zamów przejazd" ]
    , p [ class "panel__opis" ] [ text "Kliknij mapę, aby ustawić punkt, albo wpisz współrzędne." ]
    , div [ class "segment", attribute "role" "group", attribute "aria-label" "Który punkt ustawiasz na mapie" ]
        [ przyciskSegmentu (z.ustawiam == Start) (UstawPunkt Start) "Ustawiam start"
        , przyciskSegmentu (z.ustawiam == Cel) (UstawPunkt Cel) "Ustawiam cel"
        ]
    , form [ class "formularz", onSubmit Zamow ]
        [ div [ class "wsp" ]
            [ poleWsp "Start, szerokość" "slat" z.startLat StartLat
            , poleWsp "Start, długość" "slon" z.startLon StartLon
            , poleWsp "Cel, szerokość" "clat" z.celLat CelLat
            , poleWsp "Cel, długość" "clon" z.celLon CelLon
            ]
        , p [ class "etykieta", id "ile-osob" ] [ text "Liczba osób" ]
        , div [ class "segment segment--liczby", attribute "role" "group", attribute "aria-labelledby" "ile-osob" ]
            (List.map
                (\n -> przyciskSegmentu (String.fromInt n == z.miejsca) (WpisanoMiejsca (String.fromInt n)) (String.fromInt n))
                [ 1, 2, 3, 4 ]
            )
        , p [ class "pasuje" ]
            [ text
                ("Pasują klasy: "
                    ++ String.join ", " (List.map .nazwa klasy)
                    ++ ". Wolnych pasujących aut: "
                    ++ String.fromInt (List.length pasujace)
                    ++ "."
                )
            ]
        , case z.stan of
            ZamPisanie (Just tresc) ->
                p [ class "blad", attribute "role" "alert" ] [ text tresc ]

            _ ->
                text ""
        , button [ type_ "submit", class "przycisk przycisk--pelny", disabled wysylanie ]
            [ text
                (if wysylanie then
                    "Wysyłanie…"

                 else
                    "Zamów przejazd"
                )
            ]
        ]
    ]


poleWsp : String -> String -> String -> Pole -> Html Msg
poleWsp etykieta idPola wartosc p =
    div [ class "pole" ]
        [ label [ for idPola ] [ text etykieta ]
        , input
            [ id idPola
            , type_ "text"
            , attribute "inputmode" "decimal"
            , required True
            , value wartosc
            , onInput (WpisanoWsp p)
            ]
            []
        ]


{-| punkty wpisane w formularzu, o ile da się je odczytać jako liczby
-}
punktyZamowienia : FormZamowienia -> List Znacznik
punktyZamowienia z =
    List.filterMap identity
        [ Maybe.map2 (\a b -> Znacznik "start" a b "S") (parsuj z.startLat) (parsuj z.startLon)
        , Maybe.map2 (\a b -> Znacznik "cel" a b "C") (parsuj z.celLat) (parsuj z.celLon)
        ]



-- przejazdy


widokPrzejazdow : Sesja -> List (Html Msg)
widokPrzejazdow s =
    [ h1 [ class "panel__tytul" ] [ text "Moje przejazdy" ]
    , case s.historia of
        HistoriaPusta ->
            text ""

        HistoriaLaduje ->
            p [ class "podpowiedz" ] [ text "Ładowanie przejazdów…" ]

        HistoriaBlad ->
            p [ class "blad" ] [ text "Nie udało się pobrać przejazdów." ]

        HistoriaGotowa [] ->
            p [ class "podpowiedz" ] [ text "Nie masz jeszcze żadnych przejazdów. Pierwszy zamówisz w zakładce „Zamów”." ]

        HistoriaGotowa lista ->
            div [ class "opinie" ]
                (p [ class "opinie__srednia" ] [ text ("Liczba przejazdów: " ++ String.fromInt (List.length lista)) ]
                    :: List.map widokWierszaPrzejazdu (List.reverse (List.sortBy .data lista))
                )
    ]


widokWierszaPrzejazdu : Przejazd -> Html Msg
widokWierszaPrzejazdu p =
    div [ class "opinia" ]
        [ div [ class "opinia__naglowek" ]
            [ span [ class "opinia__autor" ] [ text ("Auto #" ++ p.auto ++ " · " ++ String.left 16 (String.replace "T" " " p.data)) ]
            , span [ class "etykieta" ] [ text (opisStatusu p.status) ]
            ]
        , text ("Z " ++ zaokr4 p.startLat ++ ", " ++ zaokr4 p.startLon ++ " do " ++ zaokr4 p.celLat ++ ", " ++ zaokr4 p.celLon)
        , div []
            [ button [ type_ "button", class "przycisk-drugi", onClick (OtworzOpinie p.auto) ] [ text "Opinie o aucie" ] ]
        ]


{-| backend zapisuje status jako tekst ("requested" to wartość domyślna z bazy); nieznane statusy pokazujemy bez zmian
-}
opisStatusu : String -> String
opisStatusu status =
    case status of
        "requested" ->
            "Zamówiony"

        "completed" ->
            "Zakończony"

        "cancelled" ->
            "Anulowany"

        inny ->
            inny



-- opinie


widokOpinii : List Kierowca -> Sesja -> List (Html Msg)
widokOpinii flota s =
    let
        k =
            s.kom
    in
    [ h1 [ class "panel__tytul" ] [ text "Opinie o kierowcach" ]
    , if List.isEmpty s.doOceny then
        text ""

      else
        div [ class "do-oceny" ]
            (p [ class "etykieta" ] [ text "Czekają na Twoją ocenę" ]
                :: List.map
                    (\id -> button [ type_ "button", class "przycisk-drugi", onClick (WybranoKierowce id) ] [ text ("Auto #" ++ id) ])
                    s.doOceny
            )
    , div [ class "pole" ]
        [ label [ for "auto" ] [ text "Auto" ]
        , select [ id "auto", onInput WybranoKierowce ]
            (option [ value "", selected (k.wybrany == Nothing) ] [ text "Wybierz auto…" ]
                :: List.map
                    (\a -> option [ value a.id, selected (k.wybrany == Just a.id) ] [ text ("#" ++ a.id ++ " · " ++ (klasaAuta a).nazwa) ])
                    flota
            )
        ]
    , case k.lista of
        ListaPusta ->
            p [ class "podpowiedz" ] [ text "Wybierz auto z listy albo kliknij je na mapie." ]

        ListaLaduje ->
            p [ class "podpowiedz" ] [ text "Ładowanie opinii…" ]

        ListaBlad ->
            p [ class "blad" ] [ text "Nie udało się pobrać opinii." ]

        ListaGotowa [] ->
            p [ class "podpowiedz" ] [ text "Nikt jeszcze nie ocenił tego auta. Twoja opinia będzie pierwsza." ]

        ListaGotowa lista ->
            div [ class "opinie" ]
                (p [ class "opinie__srednia" ]
                    [ text
                        ("Średnia "
                            ++ jednoMiejsce (List.sum (List.map .ocena lista) / toFloat (List.length lista))
                            ++ " z "
                            ++ String.fromInt (List.length lista)
                            ++ " opinii"
                        )
                    ]
                    :: List.map widokOpinii1 lista
                )
    , case k.wybrany of
        Just id ->
            if List.member id s.doOceny then
                formularzOpinii k

            else if k.info /= Nothing then
                p [ class "komunikat komunikat--ok" ] [ text (Maybe.withDefault "" k.info) ]

            else if s.przejazd == Just id then
                p [ class "podpowiedz podpowiedz--ramka" ] [ text "Jedziesz teraz tym autem. Opinię wystawisz, gdy przejazd się zakończy." ]

            else
                p [ class "podpowiedz podpowiedz--ramka" ] [ text "Opinię wystawisz po zakończonym przejeździe tym autem." ]

        Nothing ->
            text ""
    ]


widokOpinii1 : Komentarz -> Html Msg
widokOpinii1 o =
    div [ class "opinia" ]
        [ div [ class "opinia__naglowek" ]
            [ span [ class "gwiazdki", attribute "aria-label" ("Ocena " ++ String.fromInt (round o.ocena) ++ " na 5") ] [ text (gwiazdki o.ocena) ]
            , span [ class "opinia__autor" ] [ text (ukryjEmail o.autor ++ " · " ++ String.left 16 o.data) ]
            ]
        , p [] [ text o.tresc ]
        ]


gwiazdki : Float -> String
gwiazdki ocena =
    let
        n =
            clamp 0 5 (round ocena)
    in
    String.repeat n "★" ++ String.repeat (5 - n) "☆"


{-| backend zwraca pełne e-maile autorów; na ekranie pokazujemy tylko "a***@domena"
-}
ukryjEmail : String -> String
ukryjEmail email =
    case String.split "@" email of
        [ lewa, domena ] ->
            String.left 1 lewa ++ "***@" ++ domena

        _ ->
            "***"


formularzOpinii : FormKomentarzy -> Html Msg
formularzOpinii k =
    let
        wybrana =
            Maybe.withDefault 5 (String.toInt k.ocena)
    in
    form [ class "formularz nowa-opinia", onSubmit WystawKomentarz ]
        [ h2 [ class "panel__podtytul" ] [ text "Dodaj opinię" ]
        , p [ class "etykieta", id "ocena-etykieta" ] [ text "Ocena" ]
        , div [ class "ocena", attribute "role" "group", attribute "aria-labelledby" "ocena-etykieta" ]
            (List.map
                (\n ->
                    button
                        [ type_ "button"
                        , classList [ ( "ocena__gwiazdka", True ), ( "ocena__gwiazdka--pelna", n <= wybrana ) ]
                        , attribute "aria-label" (String.fromInt n ++ " na 5")
                        , attribute "aria-pressed"
                            (if n == wybrana then
                                "true"

                             else
                                "false"
                            )
                        , onClick (WpisanoOcene (String.fromInt n))
                        ]
                        [ text "★" ]
                )
                [ 1, 2, 3, 4, 5 ]
            )
        , label [ for "tresc" ] [ text "Treść" ]
        , textarea
            [ id "tresc"
            , rows 4
            , maxlength 500
            , required True
            , value k.tresc
            , onInput WpisanoTresc
            ]
            []
        , case k.blad of
            Just tresc ->
                p [ class "blad", attribute "role" "alert" ] [ text tresc ]

            Nothing ->
                text ""
        , case k.info of
            Just tresc ->
                p [ class "komunikat komunikat--ok" ] [ text tresc ]

            Nothing ->
                text ""
        , button [ type_ "submit", class "przycisk przycisk--ciemny przycisk--pelny", disabled k.wysylanie ]
            [ text
                (if k.wysylanie then
                    "Wysyłanie…"

                 else
                    "Dodaj opinię"
                )
            ]
        ]

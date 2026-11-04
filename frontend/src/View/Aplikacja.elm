module View.Aplikacja exposing (..)

import Html exposing (Html, a, button, div, header, label, main_, nav, node, p, span, text)
import Html.Attributes exposing (attribute, class, classList, id, type_)
import Html.Events exposing (on, onClick)
import Json.Decode as D
import Types exposing (..)
import Format exposing (jednoMiejsce)
import Miejsca exposing (odlegloscKm)
import Mapa3D exposing (flotaJson, punktyJson)
import Mapa2D exposing (mapa)
import View.Auta exposing (widokAut, znajdzAuto)
import View.Zamowienie exposing (punktyZamowienia, widokZamowienia)
import View.Przejazdy exposing (widokPrzejazdow)
import View.Opinie exposing (widokOpinii)


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

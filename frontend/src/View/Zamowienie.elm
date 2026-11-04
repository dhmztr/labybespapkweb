module View.Zamowienie exposing (..)

import Html exposing (Html, a, button, div, form, h1, input, label, li, p, text, ul)
import Html.Attributes exposing (attribute, class, classList, disabled, for, id, required, type_, value)
import Html.Events exposing (onInput, onSubmit)
import Types exposing (..)
import Klasy exposing (kombi, komfort, mini, xl)
import Format exposing (aut, jednoMiejsce, osob, parsuj, wolneAuta)
import Miejsca exposing (odlegloscKm)
import View.Auta exposing (kartaAuta, znajdzAuto)
import View.Konto exposing (przyciskSegmentu)


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

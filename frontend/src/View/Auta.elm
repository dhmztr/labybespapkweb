module View.Auta exposing (..)

import Html exposing (Html, button, dd, div, dl, dt, h1, h2, li, p, span, text, ul)
import Html.Attributes exposing (attribute, class, classList, id, type_)
import Html.Events exposing (onClick)
import Types exposing (..)
import Klasy exposing (klasaAuta)
import Format exposing (aut, miejsc, wolneAuta, zaokr4)
import Mapa3D exposing (auto3d)


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

module View.Przejazdy exposing (..)

import Html exposing (Html, button, div, h1, p, span, text)
import Html.Attributes exposing (class, type_)
import Html.Events exposing (onClick)
import Types exposing (..)
import Format exposing (zaokr4)


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

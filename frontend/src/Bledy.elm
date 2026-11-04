module Bledy exposing (..)

import Html exposing (a)
import Http
import Types exposing (..)


{-| Backend odrzuca hasła krótsze niż 9 znaków i e-maile bez formy a@b.c (400);
te same reguły sprawdzamy lokalnie, żeby nie marnować próby z limitu.
-}
minDlugoscHasla : Int
minDlugoscHasla =
    9


poprawnyEmail : String -> Bool
poprawnyEmail email =
    case String.split "@" email of
        [ lokalna, domena ] ->
            let
                bezSpacji s =
                    not (String.isEmpty s) && not (String.contains " " s)
            in
            bezSpacji lokalna
                && bezSpacji domena
                && (case String.split "." domena of
                        czesci ->
                            List.length czesci >= 2 && List.all (not << String.isEmpty) czesci
                   )

        _ ->
            False


sprawdzRejestracje : String -> String -> String -> Maybe String
sprawdzRejestracje email haslo powtorz =
    if not (poprawnyEmail email) then
        Just "Podaj poprawny adres e-mail."

    else if String.length haslo < minDlugoscHasla then
        Just ("Hasło jest za krótkie — minimum " ++ String.fromInt minDlugoscHasla ++ " znaków.")

    else if haslo /= powtorz then
        Just "Hasła nie są takie same."

    else
        Nothing


opisBleduRejestracji : Http.Error -> String
opisBleduRejestracji blad =
    case blad of
        Http.BadStatus 400 ->
            "Niepoprawny e-mail albo hasło krótsze niż " ++ String.fromInt minDlugoscHasla ++ " znaków."

        Http.BadStatus 409 ->
            "Konto z tym adresem e-mail już istnieje. Zaloguj się."

        _ ->
            opisBledu blad


opisBledu : Http.Error -> String
opisBledu blad =
    case blad of
        Http.BadStatus 401 ->
            "Nieprawidłowy e-mail lub hasło."

        Http.BadStatus 409 ->
            "Konto z tym adresem e-mail już istnieje."

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

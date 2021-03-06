port module Api exposing 
    (Cred
    , addServerError
    , application
    , get
    , login
    , logout
    , post
    , put
    , storeCred
    , credChanges
    )

{-| This module is responsible for communicating to the Conduit API.

It exposes an opaque Endpoint type which is guaranteed to point to the correct URL.

-}

import Api.Endpoint as Endpoint exposing (Endpoint)
import Browser
import Browser.Navigation as Nav
import Http exposing (Body, Expect)
import Json.Decode as Decode exposing (Decoder, Value, decodeString, field, string)
import Json.Encode as Encode
import Url exposing (Url)
import Username exposing (Username)



-- CRED


{-| The authentication credentials for the Viewer (that is, the currently logged-in user.)

This includes:

  - The cred's Username
  - The cred's authentication token

By design, there is no way to access the token directly as a String.
It can be encoded for persistence, and it can be added to a header
to a HttpBuilder for a request, but that's it.

This token should never be rendered to the end user, and with this API, it
can't be!

-}
type Cred
    = Cred String


credHeader : Cred -> Http.Header
credHeader (Cred str) =
    Http.header "Authorization" ("Token " ++ str)


{-| It's important that this is never exposed!

We expose `login` and `application` instead, so we can be certain that if anyone
ever has access to a `Cred` value, it came from either the login API endpoint
or was passed in via flags.

-}
credDecoder : Decoder Cred
credDecoder =
    Decode.map Cred
        (Decode.field "token" Decode.string)



-- PERSISTENCE



port onStoreChange : (Value -> msg) -> Sub msg


credChanges : (Maybe Cred -> msg) -> Sub msg
credChanges toMsg =
    let
        maybeCred : Value -> Maybe Cred
        maybeCred value = 
            let 
                _ = Debug.log "Cred Changed" value
            in
            ( Decode.decodeValue Decode.string value 
                |> Result.andThen (\str -> Decode.decodeString credDecoder str )
                |> Result.toMaybe
                )
    in
    onStoreChange (\value -> toMsg ( maybeCred value ))



storeCred : Cred -> Cmd msg
storeCred (Cred token) =
    let
        json =
            Encode.object
                [ ( "token", Encode.string token )]
    in
    storeCache (Just json)


logout : Cmd msg
logout =
    storeCache Nothing


port storeCache : Maybe Value -> Cmd msg



-- SERIALIZATION
-- APPLICATION


application :
        { init : Maybe Cred -> Url -> Nav.Key -> ( model, Cmd msg )
        , onUrlChange : Url -> msg
        , onUrlRequest : Browser.UrlRequest -> msg
        , subscriptions : model -> Sub msg
        , update : msg -> model -> ( model, Cmd msg )
        , view : model -> Browser.Document msg
        }
    -> Program Value model msg
application config =
    let
        init flags url navKey =
            let
                maybeCred =
                    Decode.decodeValue Decode.string flags
                        |> Result.andThen (Decode.decodeString credDecoder)
                        |> Result.toMaybe
            in
            config.init maybeCred url navKey
    in
    Browser.application
        { init = init
        , onUrlChange = config.onUrlChange
        , onUrlRequest = config.onUrlRequest
        , subscriptions = config.subscriptions
        , update = config.update
        , view = config.view
        }




-- HTTP


get : Endpoint -> Maybe Cred -> Decoder a -> (Result Http.Error a -> msg) -> Cmd msg
get url maybeCred decoder msg =
    Endpoint.request
        { method = "GET"
        , url = url
        , expect = Http.expectJson msg decoder
        , headers =
            case maybeCred of
                Just cred ->
                    [ credHeader cred ]

                Nothing ->
                    []
        , body = Http.emptyBody
        , timeout = Nothing
        , tracker = Nothing
        }


put : Endpoint -> Cred -> Body -> Decoder a -> (Result Http.Error a -> msg) -> Cmd msg
put url cred body decoder msg =
    Endpoint.request
        { method = "PUT"
        , url = url
        , expect = Http.expectJson msg decoder
        , headers = [ credHeader cred ]
        , body = body
        , timeout = Nothing
        , tracker = Nothing
        }


post : Endpoint -> Maybe Cred -> Body -> Decoder a -> (Result Http.Error a -> msg) -> Cmd msg
post url maybeCred body decoder msg =
    Endpoint.request
        { method = "POST"
        , url = url
        , expect = Http.expectJson msg decoder 
        , headers =
            case maybeCred of
                Just cred ->
                    [ credHeader cred ]

                Nothing ->
                    []
        , body = body
        , timeout = Nothing
        , tracker = Nothing
        }


delete : Endpoint -> Cred -> Body -> Decoder a -> (Result Http.Error a -> msg) -> Cmd msg
delete url cred body decoder msg =
    Endpoint.request
        { method = "DELETE"
        , url = url
        , expect = Http.expectJson msg decoder
        , headers = [ credHeader cred ]
        , body = body
        , timeout = Nothing
        , tracker = Nothing
        }


login : Http.Body -> (Result Http.Error Cred -> msg) -> Cmd msg
login body msg =
    post Endpoint.login Nothing body credDecoder msg





-- ERRORS


addServerError : List String -> List String
addServerError list =
    "Server error" :: list


{-| Many API endpoints include an "errors" field in their BadStatus responses.
-}
-- decodeErrors : Http.Error -> List String
-- decodeErrors error =
--     case error of
--         Http.BadStatus response ->
--             response.body
--                 |> decodeString (field "errors" errorsDecoder)
--                 |> Result.withDefault [ "Server error" ]

--         err ->
--             [ "Server error" ]


errorsDecoder : Decoder (List String)
errorsDecoder =
    Decode.keyValuePairs (Decode.list Decode.string)
        |> Decode.map (List.concatMap fromPair)


fromPair : ( String, List String ) -> List String
fromPair ( field, errors ) =
    List.map (\error -> field ++ " " ++ error) errors



-- LOCALSTORAGE KEYS


cacheStorageKey : String
cacheStorageKey =
    "cache"


credStorageKey : String
credStorageKey =
    "cred"

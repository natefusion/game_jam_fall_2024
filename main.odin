package main;
import rl "vendor:raylib";
import "core:fmt";
import "core:math/rand";
import "core:math";
import "core:slice";

Suit :: enum {
    Clubs,
    Diamonds,
    Hearts,
    Spades,
}

Rank :: enum {
    Ace,
    Two,
    Three,
    Four,
    Five,
    Six,
    Seven,
    Eight,
    Nine,
    Ten,
    Jack,
    Queen,
    King,
}

Orientation :: enum { Front, Back }

Card :: struct {
    suit: Suit,
    rank: Rank,
    value: int,
    x: int,
    y: int,
    orientation: Orientation,
}

TokenValue :: enum {
    One = 1, Two = 2, Four = 4, Eight = 8,
}

Token :: struct {
    value: TokenValue,
    x: int,
    y: int,
    is_betting: bool,
}

Cursor_Grasp :: enum { Card, Token, None }

GameState :: enum {
    Wait_For_Bet,
    Deal_Many_Cards,
    Deal_Card,
    Wait_For_Hit_Or_Stand,
    Take_Hit,
    Stand_Off,
    Receive_Tokens,
    Relinquish_Tokens,
    Relinquish_Cards,
    Count_Cards,
    Dealer_Hit_Or_Stand,
    Dealer_Take_Hit,
    Dealer_Count_Cards,
    Exposition,
    Give_Advice,
}

State :: struct {
    current_state : GameState,
    next_state : GameState,
    deck : [dynamic]Card,
    dealer_hand : [dynamic]Card,
    hand : [dynamic]Card,
    tokens : [dynamic]Token,
    player_stand : bool,
    player_hit : bool,
    anim_index: int,
    finished_playing_animation : bool,
    action_complete : bool,
    player_took_advice_amount : int,
    daemon_should_lie : int,
    daemon_says_to_hit : bool,
}

// Global variables :)

card_width :: 75;
card_height :: 107;

token_width :: 52;
token_height :: 52;

colorShader : rl.Shader;
colorLoc : i32;

see_through_shader : rl.Shader;
see_through_Loc : i32;

club_texture : rl.Texture;
heart_texture : rl.Texture;
diamond_texture : rl.Texture;
spade_texture : rl.Texture;
backside_texture : rl.Texture;
token_texture : rl.Texture;
daemon_texture : [2]rl.Texture;
bubble_texture : rl.Texture;
pointer_texture : rl.Texture;

hand_location : rl.Rectangle = {
    width = cast(f32)(card_width * 3 + card_width/2),
    height = cast(f32)(card_height + card_height/3),
    x = 500 - cast(f32)(card_width * 3 + card_width/2)/2,
    y = 550,
};

bet_location : rl.Rectangle = {
    width = 3 * (token_width + token_width/3),
    height = token_height + token_height/3,
    x = hand_location.x + hand_location.width + 2,
    y = hand_location.y - hand_location.height/2,
};

bank_location : rl.Rectangle = {
    width = 3 * (token_width + token_width/3),
    height = token_height + token_height/3,
    x = hand_location.x + hand_location.width + 2,
    y = hand_location.y - hand_location.height/2 + bet_location.height + 2,
};

// End global variables

load_textures :: proc() {
    club := rl.LoadImage("./resources/club.png");
    club_texture = rl.LoadTextureFromImage(club);
    rl.UnloadImage(club);

    spade := rl.LoadImage("./resources/spade.png");
    spade_texture = rl.LoadTextureFromImage(spade);
    rl.UnloadImage(spade);

    diamond := rl.LoadImage("./resources/diamond.png");
    diamond_texture = rl.LoadTextureFromImage(diamond);
    rl.UnloadImage(diamond);

    heart := rl.LoadImage("./resources/heart.png");
    heart_texture = rl.LoadTextureFromImage(heart);
    rl.UnloadImage(heart);

    backside := rl.LoadImage("./resources/backside.png");
    backside_texture = rl.LoadTextureFromImage(backside);
    rl.UnloadImage(backside);

    token := rl.LoadImage("./resources/token.png");
    token_texture = rl.LoadTextureFromImage(token);
    rl.UnloadImage(token);

    daemon := rl.LoadImage("./resources/daemon_mouth_open.png");
    daemon_texture[0] = rl.LoadTextureFromImage(daemon);
    rl.UnloadImage(daemon);

    daemon = rl.LoadImage("./resources/daemon_mouth_closed.png");
    daemon_texture[1] = rl.LoadTextureFromImage(daemon);
    rl.UnloadImage(daemon);
    
    bubble := rl.LoadImage("./resources/bubble.png");
    bubble_texture = rl.LoadTextureFromImage(bubble);
    rl.UnloadImage(bubble);
    
    pointer := rl.LoadImage("./resources/pointer.png");
    pointer_texture = rl.LoadTextureFromImage(pointer);
    rl.UnloadImage(pointer);
    
    colorShader = rl.LoadShader(nil, "./resources/colorShader.fs");
    colorLoc = rl.GetShaderLocation(colorShader, "color");

    see_through_shader = rl.LoadShader(nil, "./resources/see_through.fs");
    see_through_Loc = rl.GetShaderLocation(see_through_shader, "color");
}

init_deck :: proc(deck: ^[dynamic]Card) {
    rank := 0;
    suit := 0;

    for _ in 0..<52 {
        value := rank+1 if rank < 10 else 10;
        card : Card = {suit=cast(Suit)suit, value=value, rank=cast(Rank)rank, orientation=.Front, x=0, y=0};
        append(deck, card);
        rank = (rank + 1) % 13;
        suit = (suit + 1) % 4;
    }

    rand.shuffle(deck[:]);
}

color_to_vec4 :: proc(color: rl.Color) -> [4]f32 {
    return { cast(f32)color.r, cast(f32)color.g, cast(f32)color.b, cast(f32)color.a } / 255;
}

receive_tokens :: proc(tokens: ^[dynamic]Token, reward: []Token) {
    for token in reward { append(tokens, token); }
}

count_cards :: proc(hand : []Card, every_card: bool = false) -> (total : int) {
    if every_card {
        for card in hand { total += card.value; }
    } else {
        for card in hand { if card.orientation == .Front { total += card.value; } }
    }
    
    return;
}

count_tokens :: proc(tokens: []Token) -> (total : int) {
    for token in tokens {
        total += cast(int)token.value;
    }

    return;
}

move_tokens :: proc(tokens: []Token) {
    x := cast(int)(bank_location.x);
    y := cast(int)(bank_location.y+bank_location.height/8);

    amount := cast(int)bank_location.width / len(tokens);
    for &token in tokens {
        token.x = x;
        token.y = y;
        x += amount;
    }
}

draw_daemon :: proc(state: ^State) {
    pos := rl.Vector2 { hand_location.x - 100,  hand_location.y };
    real_color := color_to_vec4(rl.WHITE);
    @(static) i : f32 = 0;
    if state.anim_index % 5 == 0 {
        i += 1 / math.TAU;
    }
    real_color.x *= math.sin(i);
    real_color.y *= math.cos(i);
    real_color.z *= math.tan(i);
    rl.SetShaderValue(see_through_shader, see_through_Loc, &real_color, rl.ShaderUniformDataType.VEC4);
    rl.BeginShaderMode(see_through_shader);
    rl.DrawTextureEx(daemon_texture[0], pos, 0, 1, rl.WHITE);
    rl.EndShaderMode();

    if i >= 1 {
        i = 0;
    }
}

draw_bubble :: proc() {
    rl.DrawTexture(bubble_texture, 0, 1000 - 280, rl.WHITE);
}

draw_pointer :: proc () {
    m := rl.GetMousePosition();
    m.x -= 25;
    real_color := color_to_vec4(rl.WHITE);
    real_color.x *= (m.x / 1000.);
    real_color.y *= (m.y / 1000.);
    real_color.z *=  real_color.x * real_color.y;
    rl.SetShaderValue(see_through_shader, see_through_Loc, &real_color, rl.ShaderUniformDataType.VEC4);
    rl.BeginShaderMode(see_through_shader);
    rl.DrawTextureEx(pointer_texture, m, 0, 0.04, rl.WHITE);
    rl.EndShaderMode();
}

draw_card :: proc(card: Card) {
    draw_suit :: proc(suit: Suit, x: int, y: int) -> (color: rl.Color) {
        texture: rl.Texture;
        switch suit {
            case .Clubs: {
                color = rl.GREEN;
                texture = club_texture;
            }
            case .Diamonds: {
                color = rl.BLUE;
                texture = diamond_texture;
            }
            case .Hearts: {
                color = rl.RED;
                texture = heart_texture;
            }
            
            case .Spades: {
                color = rl.BLACK;
                texture = spade_texture;
            }
        }

        real_color := color_to_vec4(color);
        rl.SetShaderValue(colorShader, colorLoc, &real_color, rl.ShaderUniformDataType.VEC4);
        rl.BeginShaderMode(colorShader);
        rl.DrawTexture(texture, cast(i32)x, cast(i32)y, rl.WHITE);
        rl.EndShaderMode();
        
        return;
    }

    draw_rank :: proc(rank: Rank, value: int, x: int, y: int, color: rl.Color) {
        text : cstring;
        switch rank {
            case .Ace: {
                if value == 1 {
                    text = "A1";
                } else if value == 11 {
                    text = "A11";
                }
            }
            case .Two: text = "2";
            case .Three: text = "3";
            case .Four: text = "4";
            case .Five: text = "5";
            case .Six: text = "6";
            case .Seven: text = "7";
            case .Eight: text = "8";
            case .Nine: text = "9";
            case .Ten: text = "10";
            case .Jack: text = "J";
            case .Queen: text = "Q";
            case .King: text = "K";
        }

        rl.DrawText(text, cast(i32)x, cast(i32)y, 40, color);
    }


    rec := rl.Rectangle {
        x=cast(f32)card.x,
        y=cast(f32)card.y,
        width=cast(f32)card_width,
        height=cast(f32)card_height
    };
    
    rl.DrawRectangleRoundedLines(rec, .5, 1, 1, rl.BLACK);
    rl.DrawRectangleRounded(rec, .5, 1, rl.WHITE);
    
    switch card.orientation {
        case .Front: {
            color := draw_suit(card.suit, card.x, card.y);
            draw_rank(card.rank, card.value, card.x + 10, card.y, color);
        }
        case .Back: {
            rl.DrawTexture(backside_texture, cast(i32)card.x, cast(i32)card.y, rl.WHITE);

        }
    }
}

draw_text_box :: proc(text: []cstring, colors: []rl.Color, no_input: bool = false) {
    text_size : i32 = 30;
    x : i32 = 2;
    y : i32 = 1000 - text_size*4;
    if no_input == false {
        for i in 0..<len(text)-1 {
            rl.DrawText(text[i], x, y, text_size, colors[i]);
            y += text_size;
        }

        y = 1000 - text_size;
        rl.DrawText(slice.last(text[:]), x, y, text_size, rl.BLACK);
    } else {
        for i in 0..<len(text) {
            rl.DrawText(text[i], x, y, text_size, colors[i]);
            y += text_size;
        }
    }
    draw_bubble();
}

draw_token :: proc(token: Token) {
    text : cstring;
    switch token.value {
        case .One: text = "1";
        case .Two: text = "2";
        case .Four: text = "4";
        case .Eight: text = "8";
    }

    rl.DrawTexture(token_texture, cast(i32)token.x, cast(i32)token.y, rl.WHITE);
    rl.DrawText(text, cast(i32)(token.x + token_width/2 - 6), cast(i32)(token.y + token_height/4), 30, rl.BLACK);
}

draw_table :: proc() {
    rl.DrawRingLines(center={500.,250.}, innerRadius=250., outerRadius=500., startAngle=0, endAngle=180, segments=1, color=rl.BLACK);
    rl.DrawLine(250, 251, 751, 249, rl.BLACK);

    width := cast(i32)(hand_location.width);
    height := cast(i32)(hand_location.height);
    x := cast(i32)(hand_location.x);
    y := cast(i32)(hand_location.y);
    rl.DrawRectangleLines(posX=x, posY=y, width=width, height=height, color=rl.BLACK);
    rl.DrawText("Hand", x + 90, y + height/2 - 15, 30, rl.BLACK);

    rl.DrawRectangleLines(posX=cast(i32)bet_location.x, posY=cast(i32)bet_location.y, width=cast(i32)bet_location.width, height=cast(i32)bet_location.height, color=rl.BLACK);
    rl.DrawText("Betting Zone", x + width + 7, y - token_height, 30, rl.BLACK);
    
    rl.DrawRectangleLines(posX=cast(i32)bank_location.x, posY=cast(i32)bank_location.y, width=cast(i32)bank_location.width, height=cast(i32)bank_location.height, color=rl.BLACK);
    rl.DrawText("Bank", x + width + 65, cast(i32)(bank_location.y + bank_location.height/2 - 15), 30, rl.BLACK);
}

card_pickup_logic :: proc(hand : ^[dynamic]Card, stuck_to_cursor: ^Cursor_Grasp) {
    if len(hand) == 0 { return; }
    picked_card := false;
    point := rl.GetMousePosition();
    i := len(hand)-1;
    to_move := -1;
    
    #reverse for &card in hand {
        is_clicking := rl.IsMouseButtonPressed(rl.MouseButton.LEFT);

        rec := rl.Rectangle {
            width=cast(f32)card_width,
            height=cast(f32)card_height,
            x=cast(f32)card.x,
            y=cast(f32)card.y,
        };
        
        mouse_in_card := rl.CheckCollisionPointRec(point, rec);

        if !picked_card && stuck_to_cursor^ == .None && mouse_in_card && is_clicking {
            stuck_to_cursor^ = .Card;
            to_move = i;
            picked_card = true;
        }

        i -= 1;
    }

    if to_move > -1 {
        card := hand[to_move];
        ordered_remove(hand, to_move);
        append(hand, card);
    }
    
    if stuck_to_cursor^ == .Card {
        card := slice.last_ptr(hand[:]);
        if card.rank == .Ace && rl.IsKeyPressed(rl.KeyboardKey.A) {
            if card.value == 1 {
                card.value = 11;
            } else if card.value == 11 {
                card.value = 1;
            }
        }
        is_clicking := rl.IsMouseButtonPressed(rl.MouseButton.LEFT);
        if is_clicking && !picked_card {
            if rl.CheckCollisionPointRec(point, hand_location) {
                stuck_to_cursor^ = .None;
            }
        } else {
            point := rl.GetMousePosition();
            card.x = cast(int)(point.x - cast(f32)card_width/2);
            card.y = cast(int)(point.y - cast(f32)card_height/2);
        }
    }
}

token_pickup_logic :: proc(state: ^State, stuck_to_cursor: ^Cursor_Grasp) {
    pickup_token :: proc(tokens : ^[dynamic]Token, stuck_to_cursor: ^Cursor_Grasp) -> (picked_up_token : bool) {
        point := rl.GetMousePosition();
        to_move := -1;
        i := len(tokens)-1;

        #reverse for &token in tokens {
            is_clicking := rl.IsMouseButtonPressed(rl.MouseButton.LEFT);

            rec := rl.Rectangle {
                width=cast(f32)token_width,
                height=cast(f32)token_height,
                x=cast(f32)token.x,
                y=cast(f32)token.y
            };
            
            mouse_in_token := rl.CheckCollisionPointRec(point, rec);

            if !picked_up_token && stuck_to_cursor^ == .None && mouse_in_token && is_clicking {
                to_move = i;
                picked_up_token = true;
                stuck_to_cursor^ = .Token;
            }

            i -= 1;
        }

        if to_move > -1 {
            token := tokens[to_move];
            ordered_remove(tokens, to_move);
            append(tokens, token);
        }

        return;
    }

    picked_up_token := pickup_token(&state.tokens, stuck_to_cursor);

    point := rl.GetMousePosition();
    if stuck_to_cursor^ == .Token {
        token := slice.last_ptr(state.tokens[:]);
        is_clicking := rl.IsMouseButtonPressed(rl.MouseButton.LEFT);
        if is_clicking && !picked_up_token {
            betting := rl.CheckCollisionPointRec(point, bet_location);
            saving := rl.CheckCollisionPointRec(point, bank_location);
            if betting || saving {
                stuck_to_cursor^ = .None;
            }

            if betting {
                token.is_betting = true;
            } else if saving {
                token.is_betting = false;
            }
        } else {
            token.x = cast(int)(point.x - cast(f32)token_width/2);
            token.y = cast(int)(point.y - cast(f32)token_height/2);
        }
    }
}

daemon_animate :: proc(state: ^State) {
    if state.anim_index % 10 == 0 {
        temp := daemon_texture[0];
        daemon_texture[0] = daemon_texture[1];
        daemon_texture[1] = temp;
    }
}

play_exposition_anim :: proc(state: ^State) -> bool {
    daemon_animate(state);

    draw_text_box({"I see you're playing Blackjack. I can help you win big!",
                   "You can trust me.",
                   "Press SPACE to continue."},
                  {rl.BLACK, rl.RED, rl.BLACK});
                   
    return false;
}

player_should_hit :: proc(dealer_total, player_total : int) -> bool {
    return player_total < dealer_total;
}

play_deal_card_anim :: proc(state: ^State, index: int) -> bool {
    card := slice.last_ptr(state.hand[:]);
    card.x = cast(int)hand_location.x;
    card.y = cast(int)hand_location.y;

    return true;
}

play_wait_for_bet_anim :: proc(state: ^State) -> bool {
    daemon_animate(state);
    draw_text_box({"Place your tokens in the Betting Zone.","Press SPACE to confirm your bet."}, {rl.BLACK, rl.BLACK});

    return false;
}

play_give_advice_anim :: proc(state: ^State) -> bool {
    daemon_animate(state);
    directions : cstring = "H to hit, S to stand";
    if state.daemon_should_lie == 0 {
        if state.daemon_says_to_hit {
            draw_text_box({"You should hit", directions}, {rl.BLACK,rl.BLACK});
        } else {
            draw_text_box({"You should stand", directions}, {rl.BLACK,rl.BLACK});            
        }
    } else {
        if state.daemon_says_to_hit {
            draw_text_box({"You should stand", directions}, {rl.BLACK,rl.BLACK});
        } else {
            draw_text_box({"You should hit", directions}, {rl.BLACK,rl.BLACK});            
        }
    }
    
    return false;
}

play_dealer_deal_card_anim :: proc(state: ^State) -> bool {
    if state.anim_index == 0 {
        card := slice.last_ptr(state.dealer_hand[:]);
        card.x = cast(int)(state.dealer_hand[len(state.dealer_hand)-2].x + card_width/2);
        card.y = cast(int)hand_location.y - 250;
        return false;
    } else if state.anim_index > 10 {
        return true;
    }

    return false;
}

play_deal_many_cards_anim :: proc(state: ^State, index: int) -> bool {
    x := 0;
    for &card in state.hand {
        card.x = cast(int)hand_location.x + x;
        x += cast(int)hand_location.width/2 + 2;
        card.y = cast(int)hand_location.y;
    }

    x = 0
    for &card in state.dealer_hand {
        card.x = cast(int)hand_location.x + x;
        x += cast(int)hand_location.width/2 + 2;
        card.y = cast(int)hand_location.y - 250;
    }
    return true;
}

play_hit_animation :: proc(index: int) -> bool {
    if index < 50 {
        rl.DrawText("Took a hit!", 0, 0, 50, rl.RED);
        return false;
    }
    return true;
}
play_stand_animation :: proc(index: int) -> bool { return true; }
play_receive_tokens_animation :: proc(index: int) -> bool {
    if index < 400 {
        draw_text_box({"You won! See, ", "You CAN trust me!"}, {rl.BLACK, rl.RED}, no_input=true);
        return false;
    }
    
    return true;
}
play_relinquish_tokens_animation :: proc(state: ^State) -> bool {
    if state.anim_index < 400 {
        draw_text_box({"You lost, OOPS!", "Well, Nobody's perfect"}, {rl.BLACK, rl.BLACK}, no_input=true);
        return false;
    }
    
    return true;
}
play_relinquish_cards_animation :: proc(index: int) -> bool { return true; }

placed_bet :: proc(tokens: []Token) -> bool {
    for x in tokens {
        if x.is_betting {
            return true;
        }
    }

    return false;
}

state_machine_logical :: proc(state: ^State) {
    if state.current_state != state.next_state {
        state.finished_playing_animation = false;
        state.action_complete = false;
        state.current_state = state.next_state;
        state.anim_index = 0;
    }

    switch state.current_state {
        case .Exposition: {
            if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
                state.next_state = .Wait_For_Bet;
            }
        }
        case .Wait_For_Bet: {
            if rl.IsKeyPressed(rl.KeyboardKey.SPACE) && placed_bet(state.tokens[:]) {
                state.next_state = .Deal_Many_Cards;
            }
        }
        case .Deal_Many_Cards: {
            if !state.action_complete {
                card1 := pop_front(&state.deck);
                card2 := pop_front(&state.deck);
                card3 := pop_front(&state.deck);
                card4 := pop_front(&state.deck);
                card3.orientation = .Back;
                append(&state.dealer_hand, card1, card3);
                append(&state.hand, card2, card4);

                state.action_complete = true;
            }

            if state.finished_playing_animation {
                state.next_state = .Give_Advice;
            }
        }
        case .Give_Advice: {
            if !state.action_complete {
                dealer_total := count_cards(state.dealer_hand[:], every_card=true);
                player_total := count_cards(state.dealer_hand[:], every_card=true);
                state.daemon_says_to_hit = player_should_hit(dealer_total, player_total);
                state.daemon_should_lie = rand.int_max(2);
                state.action_complete = true;
            }

            if rl.IsKeyPressed(rl.KeyboardKey.H) {
                state.next_state = .Take_Hit;
            } else if  rl.IsKeyPressed(rl.KeyboardKey.S) {
                state.next_state = .Stand_Off;
            }
        }
        case .Deal_Card: {
            if !state.action_complete {
                card := pop_front(&state.deck);
                append(&state.hand, card);
                state.action_complete = true;
            }

            if state.finished_playing_animation {
                state.next_state = .Count_Cards;
            }
        }
        case .Count_Cards: {
            if state.finished_playing_animation {
                player_total := count_cards(state.hand[:]);
                if player_total > 21 {
                    state.next_state = .Relinquish_Tokens;
                } else {
                    state.next_state = .Dealer_Hit_Or_Stand;
                }
            }
            
        }
        case .Dealer_Count_Cards: {
            if state.finished_playing_animation {
                dealer_total := count_cards(state.dealer_hand[:]);
                if dealer_total > 21 {
                    state.next_state = .Receive_Tokens;
                } else if dealer_total <= 16 {
                    state.next_state = .Dealer_Take_Hit;
                } else {
                    player_total := count_cards(state.hand[:]);
                    if player_total > dealer_total {
                        state.next_state = .Receive_Tokens;
                    } else if player_total < dealer_total {
                        state.next_state = .Relinquish_Tokens;
                    }
                }
            }
        }
        case .Wait_For_Hit_Or_Stand: {
            if rl.IsKeyPressed(rl.KeyboardKey.H) {
                state.next_state = .Take_Hit;
            } else if  rl.IsKeyPressed(rl.KeyboardKey.S) {
                state.next_state = .Stand_Off;
            }
        }
        case .Dealer_Hit_Or_Stand: {
            if state.finished_playing_animation {
                for &card in state.dealer_hand {
                    card.orientation = .Front;
                }
                dealer_total := count_cards(state.dealer_hand[:]);
                hit_or_stand := true if dealer_total <= 16 else false;
                
                if hit_or_stand {
                    state.next_state = .Dealer_Take_Hit;
                } else {
                    state.next_state = .Dealer_Count_Cards;
                }
            }
        }
        case .Take_Hit: {
            if state.finished_playing_animation {
                state.next_state = .Deal_Card;
            }
        }
        case .Stand_Off: {
            // dealer_total := count_cards(state.dealer_hand[:]);
            // player_total := count_cards(state.hand[:]);
            // if !(player_total <= 21 && (dealer_total > 21 || player_total > dealer_total)) {
            //     state.player_lost = true;
            // }

            // if state.finished_playing_animation {
            //     if state.player_lost {
            //         state.next_state = .Relinquish_Tokens;
            //     } else {
            //         state.next_state = .Dealer_Hit_Or_Stand;
            //     }
            // }

            if state.finished_playing_animation {
                state.next_state = .Dealer_Hit_Or_Stand;
            }
        }
        case .Dealer_Take_Hit: {
            if !state.action_complete {
                card := pop_front(&state.deck);
                append(&state.dealer_hand, card);
                                
                state.action_complete = true;
            }

            if state.finished_playing_animation {
                state.next_state = .Dealer_Count_Cards;
            }
        }
        case .Receive_Tokens: {
            if !state.action_complete {
                for &card in state.dealer_hand {
                    card.orientation = .Front;
                }
                len := len(state.tokens);
                for i in 0..<len {
                    if state.tokens[i].is_betting {
                        append(&state.tokens, state.tokens[i]);
                    }
                }
                state.action_complete = true;
            }

            if state.finished_playing_animation {
                state.next_state = .Relinquish_Cards;
            }
        }
        case .Relinquish_Tokens: {
            if !state.action_complete {
                for &card in state.dealer_hand {
                    card.orientation = .Front;
                }
                state.action_complete = true;
            }

            if state.finished_playing_animation {
                
                i := 0;
                for i < len(state.tokens) {
                    if state.tokens[i].is_betting {
                        unordered_remove(&state.tokens, i);
                        i -= 1;
                    }
                    i += 1;
                }
                state.next_state = .Relinquish_Cards;
            }
        }
        case .Relinquish_Cards: {
            if state.finished_playing_animation {
                state.player_stand = false;
                state.player_hit = false;
                
                for len(state.hand) > 0 {
                    append(&state.deck, pop(&state.hand));
                }

                for len(state.dealer_hand) > 0 {
                    append(&state.deck, pop(&state.dealer_hand));
                }

                for &token in state.tokens {
                    token.is_betting = false;
                }
                
                state.next_state = .Wait_For_Bet;
            }
        }
    }

}

state_machine_visual :: proc(state: ^State) {
    if !state.finished_playing_animation {
        switch state.current_state {
            case .Wait_For_Bet:      state.finished_playing_animation = play_wait_for_bet_anim(state);
            case .Deal_Many_Cards:   state.finished_playing_animation = play_deal_many_cards_anim(state, state.anim_index);
            case .Deal_Card:         state.finished_playing_animation = play_deal_card_anim(state, state.anim_index);
            case .Take_Hit:          state.finished_playing_animation = play_hit_animation(state.anim_index);
            case .Receive_Tokens:    state.finished_playing_animation = play_receive_tokens_animation(state.anim_index);
            case .Relinquish_Tokens: state.finished_playing_animation = play_relinquish_tokens_animation(state);
            case .Relinquish_Cards:  state.finished_playing_animation = play_relinquish_cards_animation(state.anim_index);
            case .Wait_For_Hit_Or_Stand: state.finished_playing_animation = true;
            case .Stand_Off: state.finished_playing_animation = play_stand_animation(state.anim_index);
            case .Count_Cards: state.finished_playing_animation = true;
            case .Dealer_Hit_Or_Stand: state.finished_playing_animation = true;
            case .Dealer_Take_Hit: state.finished_playing_animation = play_dealer_deal_card_anim(state);
            case .Dealer_Count_Cards: state.finished_playing_animation = true;
            case .Exposition: state.finished_playing_animation = play_exposition_anim(state);
            case .Give_Advice: state.finished_playing_animation = play_give_advice_anim(state);
        }
    }

    for card in state.hand { draw_card(card); }
    for card in state.dealer_hand { draw_card(card); }
    for token in state.tokens { draw_token(token); }
    draw_daemon(state);
    state.anim_index += 1;
}

main :: proc() {
    rl.InitWindow(1000, 1000, "Blackjack");
    rl.SetTargetFPS(60);
    rl.HideCursor();

    load_textures();

    state : State;
    state.player_stand = false;
    state.player_hit = false;
    state.action_complete = false;
    state.current_state = .Exposition;
    state.next_state = .Exposition;
    
    init_deck(&state.deck);

    starting_tokens : []Token = {
        {value=.One},
        {value=.One},
        {value=.Two},
        {value=.Two},
        {value=.Four},
        {value=.Eight}
    };

    for x in starting_tokens {
        append(&state.tokens, x);
    }

    move_tokens(state.tokens[:]);

    stuck_to_cursor : Cursor_Grasp = .None;

    // rl.SetShaderValue(see_through_shader, backgroundLoc, &background_texture, rl.ShaderUniformDataType.SAMPLER2D);

    for !rl.WindowShouldClose() {
        // Logic
        card_pickup_logic(&state.hand, &stuck_to_cursor);
        token_pickup_logic(&state, &stuck_to_cursor);
        state_machine_logical(&state);

        if rl.IsKeyPressed(rl.KeyboardKey.P) {
            fmt.println("Current State: ", state.current_state);
            fmt.println("Next state: ", state.next_state);
            fmt.println("Hand: ", state.hand);
            fmt.println("Dealer Hand: ", state.dealer_hand);
            // fmt.println("tokens: ", state.tokens);
            fmt.println();
        }
        // End Logic
        
        rl.BeginDrawing();
        rl.ClearBackground(rl.RAYWHITE);
        draw_table();
        state_machine_visual(&state);
        draw_pointer();        
        rl.EndDrawing();
    }

    rl.UnloadShader(colorShader);
    rl.CloseWindow();
}

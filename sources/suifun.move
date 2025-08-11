module suifun::suifun {

    use sui::url::Url;
    use std::string::String;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::dynamic_field;
    use sui::sui::SUI;
    use sui::event;
    use suifun::utils;

    // Error codes
    const E_INVALID_FEE_BASIS: u64 = 1;
    const E_INVALID_VIRTUAL_TOKEN_RESERVES: u64 = 2;
    const E_INVALID_VIRTUAL_SUI_RESERVES: u64 = 3;
    const E_INVALID_TOKEN_TOTAL_SUPPLY: u64 = 4;
    const E_CURVE_NOT_FOUND: u64 = 5;
    const E_INSUFFICIENT_BALANCE: u64 = 6;
    const E_ZERO_AMOUNT: u64 = 7;
    const E_CURVE_GRADUATED: u64 = 8;
    const E_INVALID_SLIPPAGE: u64 = 9;
    const E_INVALID_CURVE_STATE: u64 = 10;


    const MAX_FEE_BASIS_POINTS: u16 = 10000;
    /// Admin capability for managing the protocol
    public struct AdminCap has key {
        id: UID,
    }

    public struct SUIFUNTOKEN has drop {}

    #[allow(lint(coin_field))]
    public struct SUICURVE has key, store {
        id: UID,
        token_vault: Balance<SUIFUNTOKEN>,
        sui_vault: Balance<SUI>,
        virtual_token_reserves: u64,
        virtual_sui_reserves: u64,
        real_token_reserves: u64,
        real_sui_reserves: u64,
        token_total_supply: u64,
        graduated: bool,
    }
    /// Global configuration for the protocol
    public struct GlobalConfig has key {
        id: UID,
        authority: address,
        fee_recipient: address,
        initial_virtual_token_reserves: u64,
        initial_virtual_sui_reserves: u64,
        initial_real_token_reserves: u64,
        token_total_supply: u64,
        fee_basis_points: u16,
        next_curve_id: u64,
        
    }

    /// Event emitted when the global configuration is updated
    public struct ConfigUpdated has copy, drop {
        authority: address,
        fee_recipient: address,
        initial_virtual_token_reserves: u64,
        initial_virtual_sui_reserves: u64,
        initial_real_token_reserves: u64,
        token_total_supply: u64,
        fee_basis_points: u16,
    }

    /// Event emitted when the authority is updated
    public struct AuthorityUpdated has copy, drop {
        old_authority: address,
        new_authority: address,
    }

    /// Initialize the protocol with default configuration
    /// This function is called once when the module is deployed 
    /// The init function does not take anything except the context so constant values are used
    fun init(ctx: &mut TxContext) {
        let sender = ctx.sender();
        let global_config = GlobalConfig {
            id: object::new(ctx),
            authority: sender,
            fee_recipient: sender,
            initial_virtual_token_reserves: 0,
            initial_virtual_sui_reserves: 0,
            initial_real_token_reserves: 0,
            token_total_supply: 0,
            fee_basis_points: 100,
            next_curve_id: 1u64,
        };
        
       // share the global config object so that anyone can create bonding curves
        sui::transfer::share_object(global_config);
        
        let admin_cap = AdminCap {
            id: sui::object::new(ctx),
        };
        sui::transfer::transfer(admin_cap, sender);
    }
    

    /// Update the global configuration (only admin)
    public entry fun update_config(
    _admin_cap: &AdminCap,
    config: &mut GlobalConfig,
    new_fee_basis: u16,
    new_fee_recipient: address,
    new_initial_virtual_token_reserves: u64,
    new_initial_virtual_sui_reserves: u64,
    new_initial_real_token_reserves: u64,
    new_token_total_supply: u64,
) {

    // Validate and update virtual token reserves with lower bound check
    assert!(new_initial_virtual_token_reserves > 0, E_INVALID_VIRTUAL_TOKEN_RESERVES);
    assert!(new_token_total_supply > 0, E_INVALID_TOKEN_TOTAL_SUPPLY);

    assert!(new_token_total_supply>new_initial_real_token_reserves, E_INVALID_TOKEN_TOTAL_SUPPLY);
    assert!(new_initial_virtual_token_reserves>new_initial_real_token_reserves, E_INVALID_VIRTUAL_TOKEN_RESERVES);
    assert!(new_fee_basis <= MAX_FEE_BASIS_POINTS, E_INVALID_FEE_BASIS);



    config.initial_virtual_token_reserves = new_initial_virtual_token_reserves;


    config.token_total_supply = new_token_total_supply;

    // Validate and update virtual SUI reserves with lower bound check
    assert!(new_initial_virtual_sui_reserves > 0, E_INVALID_VIRTUAL_SUI_RESERVES);
    
    config.initial_virtual_sui_reserves = new_initial_virtual_sui_reserves;

    // Validate and update token total supply with lower bound check
    config.token_total_supply = new_token_total_supply;

    // Validate and update fee basis points
    config.fee_basis_points = new_fee_basis;

    // Update fee recipient
    config.fee_recipient = new_fee_recipient;

    // Emit config updated event
    event::emit(ConfigUpdated {
        authority: config.authority,
        fee_recipient: config.fee_recipient,
        initial_virtual_token_reserves: config.initial_virtual_token_reserves,
        initial_virtual_sui_reserves: config.initial_virtual_sui_reserves,
        initial_real_token_reserves: config.initial_real_token_reserves,
        token_total_supply: config.token_total_supply,
        fee_basis_points: config.fee_basis_points,
    });
}


    public fun update_authority(
        admin_cap: AdminCap,
        config: &mut GlobalConfig,
        new_authority: address,
    ) {
        let old_authority = config.authority;
        config.authority = new_authority;
        
        // Emit authority updated event
        event::emit(AuthorityUpdated {
            old_authority,
            new_authority,
        });
        
        sui::transfer::transfer(admin_cap, new_authority);
    }

    ///////////////////////////// CURVE FUNCTIONS /////////////////////////////
    


    /// Create a new curve and token 
    public fun create_curve(
        config: &mut GlobalConfig,
        otw: SUIFUNTOKEN,
        name: String,
        symbol: String,
        description: Option<String>,
        icon_url: Option<Url>,
        ctx: &mut TxContext
     ){
        let (mut treasury_cap, coin_metadata) = coin::create_currency(
            otw, 
            6, // decimals
            *std::string::as_bytes(&symbol), 
            *std::string::as_bytes(&name), 
            if (option::is_some(&description)) {
                *std::string::as_bytes(option::borrow(&description))
            } else {
                b""
            }, 
            icon_url, 
            ctx
        );

        let minted_supply: Coin<SUIFUNTOKEN> = coin::mint(&mut treasury_cap, config.token_total_supply, ctx);
        // Convert coin to balance for more efficient storage
        let token_balance = coin::into_balance(minted_supply);

        let curve = SUICURVE {
            id: object::new(ctx),
            token_vault: token_balance,
            sui_vault: balance::zero<SUI>(),
            virtual_token_reserves: config.initial_virtual_token_reserves,
            virtual_sui_reserves: config.initial_virtual_sui_reserves,
            real_token_reserves: config.initial_real_token_reserves,
            real_sui_reserves: 0,
            token_total_supply: config.token_total_supply,
            graduated: false,
        };
        
        transfer::public_freeze_object(coin_metadata);
        transfer::public_freeze_object(treasury_cap);
        let curve_id = config.next_curve_id;
        dynamic_field::add<u64, SUICURVE>(&mut config.id, curve_id, curve);
        config.next_curve_id = curve_id + 1;
    }
      /// Check whether a curve exists
    public fun has_curve(config: &GlobalConfig, curve_id: u64): bool {
        dynamic_field::exists_(&config.id, curve_id)
    }

    /// Borrow immutable reference to a curve
    public fun borrow_curve(config: &GlobalConfig, curve_id: u64): &SUICURVE {
        dynamic_field::borrow<u64, SUICURVE>(&config.id, curve_id)
    }

    /// Borrow mutable reference to a curve (requires mutable GlobalConfig)
    public fun borrow_curve_mut(config: &mut GlobalConfig, curve_id: u64): &mut SUICURVE {
        dynamic_field::borrow_mut<u64, SUICURVE>(&mut config.id, curve_id)
    }

    // Remove a curve (admin-only) - only allows removing curves with zero balance
    // public entry fun remove_curve(_admin_cap: &AdminCap, config: &mut GlobalConfig, curve_id: u64) {
    //     // This will fail if the field doesn't exist
    //     let removed = dynamic_field::remove<u64, SUICURVE>(&mut config.id, curve_id);
    //     // Since this is an entry function, we need to destroy the curve properly
    //     let SUICURVE { 
    //         id, 
    //         token_vault, 
    //         sui_vault,
    //         virtual_token_reserves: _, 
    //         virtual_sui_reserves: _, 
    //         real_token_reserves: _, 
    //         real_sui_reserves, 
    //         token_total_supply: _, 
    //         graduated: _ 
    //     } = removed;
        
    //     // Security check: only allow removing curves with zero real SUI reserves
    //     assert!(real_sui_reserves == 0, E_INVALID_CURVE_STATE);
        
    //     // Properly handle the vaults by destroying the balances (must be zero)
    //     balance::destroy_zero(token_vault);
    //     balance::destroy_zero(sui_vault);
    //     object::delete(id);
    // }

    ///////////////////////////// TRADING FUNCTIONS /////////////////////////////

    /// Buy tokens with SUI using bonding curve pricing
    public entry fun buy_tokens(
        config: &mut GlobalConfig,
        curve_id: u64,
        mut payment: Coin<SUI>,
        min_tokens_out: u64,
        ctx: &mut TxContext
    ) {
        assert!(has_curve(config, curve_id), E_CURVE_NOT_FOUND);
        
        let sui_amount = coin::value(&payment);
        assert!(sui_amount > 0, E_ZERO_AMOUNT);
        
        // Extract config values to avoid referential transparency issues
        let fee_basis_points = config.fee_basis_points;
        let fee_recipient = config.fee_recipient;
        
        let curve = borrow_curve_mut(config, curve_id);
        assert!(!curve.graduated, E_CURVE_GRADUATED);
        
        // Calculate fee
        let fee_amount = utils::get_fee_amount(fee_basis_points, sui_amount);
        let sui_for_trade = sui_amount - fee_amount;
        
        // Calculate tokens to mint using bonding curve formula from utils
        let virtual_sui_reserves = curve.virtual_sui_reserves + curve.real_sui_reserves;
        let virtual_token_reserves = curve.virtual_token_reserves - curve.real_token_reserves;
        
        // Calculate tokens received for SUI input using shared utils function
        let tokens_to_mint = utils::tokens_for_sui(sui_for_trade, virtual_sui_reserves, virtual_token_reserves);
        assert!(tokens_to_mint >= min_tokens_out, E_INVALID_SLIPPAGE);
        assert!(tokens_to_mint > 0, E_ZERO_AMOUNT);
        
        // Ensure we have enough tokens in the vault
        assert!(balance::value(&curve.token_vault) >= tokens_to_mint, E_INSUFFICIENT_BALANCE);
        
        // Update curve state with overflow protection
        curve.real_sui_reserves = curve.real_sui_reserves + sui_for_trade;
        curve.real_token_reserves = curve.real_token_reserves + tokens_to_mint;
        
        // Extract tokens from vault
        let tokens_balance = balance::split(&mut curve.token_vault, tokens_to_mint);
        let tokens_coin = coin::from_balance(tokens_balance, ctx);
        
        // Handle fee and payment properly
        let fee_coin = coin::split(&mut payment, fee_amount, ctx);
        
        // Store remaining SUI payment in the curve's SUI vault
        let sui_balance = coin::into_balance(payment);
        balance::join(&mut curve.sui_vault, sui_balance);
        
        // Transfer fee to fee recipient
        transfer::public_transfer(fee_coin, fee_recipient);
        
        // Transfer tokens to buyer
        transfer::public_transfer(tokens_coin, ctx.sender());
    }

    /// Sell tokens for SUI using bonding curve pricing
    public entry fun sell_tokens(
        config: &mut GlobalConfig,
        curve_id: u64,
        tokens: Coin<SUIFUNTOKEN>,
        min_sui_out: u64,
        ctx: &mut TxContext
    ) {
        assert!(has_curve(config, curve_id), E_CURVE_NOT_FOUND);
        
        let token_amount = coin::value(&tokens);
        assert!(token_amount > 0, E_ZERO_AMOUNT);
        
        // Extract config values to avoid referential transparency issues
        let fee_basis_points = config.fee_basis_points;
        let fee_recipient = config.fee_recipient;
        
        let curve = borrow_curve_mut(config, curve_id);
        assert!(!curve.graduated, E_CURVE_GRADUATED);
        
        // Calculate SUI to return using bonding curve formula from utils
        let virtual_sui_reserves = curve.virtual_sui_reserves + curve.real_sui_reserves;
        let virtual_token_reserves = curve.virtual_token_reserves - curve.real_token_reserves;
        let sui_out = utils::sell_quote(token_amount, virtual_sui_reserves, virtual_token_reserves);
        assert!(sui_out >= min_sui_out, E_INVALID_SLIPPAGE);
        assert!(sui_out > 0, E_ZERO_AMOUNT);
        
        // Calculate fee
        let fee_amount = utils::get_fee_amount(fee_basis_points, sui_out);
        let sui_for_user = sui_out - fee_amount;
        
        // Ensure we have enough SUI in the vault
        // Need to ensure there is enough SUI in the vault for both user and fee
        let total_sui_needed = sui_out;
        assert!(balance::value(&curve.sui_vault) >= total_sui_needed, E_INSUFFICIENT_BALANCE);
        
        // Update curve state with underflow protection
        assert!(curve.real_sui_reserves >= sui_out, E_INSUFFICIENT_BALANCE);
        assert!(curve.real_token_reserves >= token_amount, E_INSUFFICIENT_BALANCE);
        curve.real_sui_reserves = curve.real_sui_reserves - sui_out;
        curve.real_token_reserves = curve.real_token_reserves - token_amount;
        
        // Return tokens to vault
        let token_balance = coin::into_balance(tokens);
        balance::join(&mut curve.token_vault, token_balance);
        
        // Extract SUI from the curve's SUI vault for user
        let user_sui_balance = balance::split(&mut curve.sui_vault, sui_for_user);
        let user_sui_coin = coin::from_balance(user_sui_balance, ctx);
        
        // Extract SUI for fee
        let fee_balance = balance::split(&mut curve.sui_vault, fee_amount);
        let fee_coin = coin::from_balance(fee_balance, ctx);
        
        // Transfer fee to fee recipient
        transfer::public_transfer(fee_coin, fee_recipient);
        
        // Transfer remaining SUI to seller
        transfer::public_transfer(user_sui_coin, ctx.sender());
    }

    ///////////////////////////// HELPER FUNCTIONS /////////////////////////////

    // Removed duplicate helper; use utils::tokens_for_sui instead

    ///////////////////////////// PRICING VIEW FUNCTIONS /////////////////////////////

    /// Get buy quote for a specific curve - how much SUI needed to buy tokens
    public fun get_buy_quote(
        config: &GlobalConfig,
        curve_id: u64,
        token_amount: u64
    ): u64 {
        assert!(has_curve(config, curve_id), E_CURVE_NOT_FOUND);
        let curve = borrow_curve(config, curve_id);
        
        let virtual_sui_reserves = curve.virtual_sui_reserves + curve.real_sui_reserves;
        let virtual_token_reserves = curve.virtual_token_reserves - curve.real_token_reserves;
        
        utils::buy_quote(token_amount, virtual_sui_reserves, virtual_token_reserves)
    }

    /// Get tokens received for a given SUI input
    public fun get_tokens_for_sui(
        config: &GlobalConfig,
        curve_id: u64,
        sui_amount: u64
    ): u64 {
        assert!(has_curve(config, curve_id), E_CURVE_NOT_FOUND);
        let curve = borrow_curve(config, curve_id);
        
        let virtual_sui_reserves = curve.virtual_sui_reserves + curve.real_sui_reserves;
        let virtual_token_reserves = curve.virtual_token_reserves - curve.real_token_reserves;
        
        utils::tokens_for_sui(sui_amount, virtual_sui_reserves, virtual_token_reserves)
    }

    /// Get sell quote for a specific curve - how much SUI received for selling tokens
    public fun get_sell_quote(
        config: &GlobalConfig,
        curve_id: u64,
        token_amount: u64
    ): u64 {
        assert!(has_curve(config, curve_id), E_CURVE_NOT_FOUND);
        let curve = borrow_curve(config, curve_id);
        
        let virtual_sui_reserves = curve.virtual_sui_reserves + curve.real_sui_reserves;
        let virtual_token_reserves = curve.virtual_token_reserves - curve.real_token_reserves;
        
        utils::sell_quote(token_amount, virtual_sui_reserves, virtual_token_reserves)
    }

    /// Get buy quote with fee included - total SUI needed including fees
    public fun get_buy_quote_with_fee(
        config: &GlobalConfig,
        curve_id: u64,
        token_amount: u64
    ): u64 {
        let base_cost = get_buy_quote(config, curve_id, token_amount);
        let fee_amount = utils::get_fee_amount(config.fee_basis_points, base_cost);
        base_cost + fee_amount
    }

    /// Get tokens received for SUI input after accounting for fees
    public fun get_tokens_for_sui_after_fee(
        config: &GlobalConfig,
        curve_id: u64,
        sui_amount: u64
    ): u64 {
        // Deduct fee from SUI input first
        let fee_amount = utils::get_fee_amount(config.fee_basis_points, sui_amount);
        let sui_for_trade = sui_amount - fee_amount;
        get_tokens_for_sui(config, curve_id, sui_for_trade)
    }

    /// Get sell quote with fee deducted - net SUI received after fees
    public fun get_sell_quote_after_fee(
        config: &GlobalConfig,
        curve_id: u64,
        token_amount: u64
    ): u64 {
        let gross_output = get_sell_quote(config, curve_id, token_amount);
        let fee_amount = utils::get_fee_amount(config.fee_basis_points, gross_output);
        gross_output - fee_amount
    }

    ///// View Functions
    public struct GlobalConfigView has copy{
           authority: address,
        fee_recipient: address,
        initial_virtual_token_reserves: u64,
        initial_virtual_sui_reserves: u64,
        initial_real_token_reserves: u64,
        token_total_supply: u64,
        fee_basis_points: u16,
    }
    public fun get_config(config: &GlobalConfig): GlobalConfigView {
        GlobalConfigView {
            authority: config.authority,
            fee_recipient: config.fee_recipient,
            initial_virtual_token_reserves: config.initial_virtual_token_reserves,    
            initial_virtual_sui_reserves: config.initial_virtual_sui_reserves,
            initial_real_token_reserves: config.initial_real_token_reserves,
            token_total_supply: config.token_total_supply,
            fee_basis_points: config.fee_basis_points,    
        }
    }

    ///// SUICURVE Accessor Functions for External Module Access /////

    
    /// Get all SUICURVE data as a view struct for external consumption
    public struct SuicurveView has copy, drop {
        virtual_token_reserves: u64,
        virtual_sui_reserves: u64,
        real_token_reserves: u64,
        real_sui_reserves: u64,
        token_total_supply: u64,
        graduated: bool,
        sui_vault_balance: u64,
        token_vault_balance: u64,
    }
    
    /// Get complete SUICURVE view
    public fun get_curve_info(curve: &SUICURVE): SuicurveView {
        SuicurveView {
            virtual_token_reserves: curve.virtual_token_reserves,
            virtual_sui_reserves: curve.virtual_sui_reserves,
            real_token_reserves: curve.real_token_reserves,
            real_sui_reserves: curve.real_sui_reserves,
            token_total_supply: curve.token_total_supply,
            graduated: curve.graduated,
            sui_vault_balance: balance::value(&curve.sui_vault),
            token_vault_balance: balance::value(&curve.token_vault),
        } 
    }
}



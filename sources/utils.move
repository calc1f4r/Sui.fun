module suifun::utils {
    
    const BASIS_POINTS: u64 = 10000;

    /// Calculate fee amount based on basis points
    public fun get_fee_amount(fee_basis_points: u16, amount: u64): u64 {
        (fee_basis_points as u64 * amount) / BASIS_POINTS
    }

    /// Calculate the SUI cost for buying tokens
    public fun buy_quote(amount: u64, virtual_sui_reserves: u64, virtual_token_reserves: u64): u64 {
        let amount = amount as u128;
        let virtual_sui_reserves = virtual_sui_reserves as u128;
        let virtual_token_reserves = virtual_token_reserves as u128;

        let sui_cost = (amount * virtual_sui_reserves) / (virtual_token_reserves - amount) + 1;
        sui_cost as u64
    }

    /// Calculate the SUI output for selling tokens
    public fun sell_quote(amount: u64, virtual_sui_reserves: u64, virtual_token_reserves: u64): u64 {
        let amount = amount as u128;
        let virtual_sui_reserves = virtual_sui_reserves as u128;
        let virtual_token_reserves = virtual_token_reserves as u128;
        
        // sui_output = (amount * virtual_sui_reserves) / (virtual_token_reserves + amount)
        let sui_output = (amount * virtual_sui_reserves) / (virtual_token_reserves + amount);
        sui_output as u64
    }

    /// Calculate tokens received for a given SUI input using the constant product formula
    /// tokens_out = (virtual_token_reserves * sui_in) / (virtual_sui_reserves + sui_in)
    public fun tokens_for_sui(sui_in: u64, virtual_sui_reserves: u64, virtual_token_reserves: u64): u64 {
        let sui_in = sui_in as u128;
        let virtual_sui_reserves = virtual_sui_reserves as u128;
        let virtual_token_reserves = virtual_token_reserves as u128;

        let tokens_out = (virtual_token_reserves * sui_in) / (virtual_sui_reserves + sui_in);
        tokens_out as u64
    }
}
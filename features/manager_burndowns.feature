Feature: Manage burndown
    As an administrator
    I want to manage burndowns
    So I have the proper burndowns available to me

    Background:
        Given I am logged in as an administrator

    Scenario: Create a new burndown
        When go the new burndown page
        And I fill out the burndown form
        Then I should have a new burndown

    Scenario: Update the pivotal token of a burndown
    Scenario: Update the name of a burndown
    Scenario: List of all burndowns
    Scenario: Delete a burndown


require('@rushstack/eslint-patch/modern-module-resolution');

module.exports = {
    rules: {
        // @layerzerolabs/eslint-config-next defines rules for turborepo-based projects
        // that are not relevant for this particular project
        'turbo/no-undeclared-env-vars': 'off',
    },
};

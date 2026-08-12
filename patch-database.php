<?php
$path = 'config/database.php';
$text = file_get_contents($path);
$old = <<<'PHP'
            'database' => env('DB_DATABASE', 'app.sqlite') === ':memory:'
                ? ':memory:'
                : database_path(env('DB_DATABASE', 'app.sqlite')),
PHP;
$new = <<<'PHP'
            'database' => (static function () {
                $db = env('DB_DATABASE', 'app.sqlite');
                if ($db === ':memory:' || str_starts_with((string) $db, '/')) {
                    return $db;
                }
                return database_path($db);
            })(),
PHP;
if (!str_contains($text, $old)) {
    fwrite(STDERR, "database.php snippet not found; Heimdall layout changed\n");
    exit(1);
}
file_put_contents($path, str_replace($old, $new, $text));

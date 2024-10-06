#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 color;

out vec4 finalColor;

void main() {
    vec4 texelColor = texture(texture0, fragTexCoord);
    finalColor = color * texelColor;
}
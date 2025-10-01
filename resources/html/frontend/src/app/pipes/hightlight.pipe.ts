// Fix for hightlight.pipe.ts
import { Pipe, PipeTransform } from '@angular/core';
import { DomSanitizer, SafeHtml } from '@angular/platform-browser';

@Pipe({
  standalone: false,
  name: 'highlight'
})
export class HighlightPipe implements PipeTransform {
  constructor(private sanitizer: DomSanitizer) {}

  transform(text: string | undefined, searchTerm: string): SafeHtml {
    if (!text || !searchTerm) {
      return text || '';
    }

    // Special case for wildcard (*) search - don't try to highlight anything
    if (searchTerm.trim() === '*') {
      return text;
    }

    // Escape special regex characters in the search term
    const escapedSearchTerm = searchTerm.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const regex = new RegExp(`(${escapedSearchTerm})`, 'gi');
    const newText = text.replace(regex, '<span class="highlight">$1</span>');

    return this.sanitizer.bypassSecurityTrustHtml(newText);
  }
}
